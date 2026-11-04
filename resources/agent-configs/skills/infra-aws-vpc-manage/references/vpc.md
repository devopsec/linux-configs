# AWS VPC — subnets, routing, NAT, security groups, endpoints, flow logs

Host firewalls (firewalld/nftables) are separate from VPC security groups; use the host-firewall specialist skill for guest rules.

## Contents
- Layout
- Create (CLI)
- IGW / NAT
- Security groups
- NACLs
- VPC endpoints
- Flow logs
- Peering / Transit Gateway
- Terraform/OpenTofu
- Troubleshooting

## Layout

```
VPC <vpc-cidr> (select from the user's approved address inventory)
├── public  <public-subnet-cidr-per-az>  load balancer / NAT gateway
├── private <private-subnet-cidr-per-az> application workloads
└── data    <data-subnet-cidr-per-az>    databases (no direct internet route)
```

Use multiple AZs where availability requires it. Plan IPv6 (`--amazon-provided-ipv6-cidr-block`) and account for public IPv4 address charges.

## Create (CLI)

```bash
VPC_ID=$(aws ec2 create-vpc --cidr-block <vpc-cidr> \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=<env>-vpc}]' --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
mk_subnet() {  # name cidr az
  aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$2" --availability-zone "$3" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$1}]" --query Subnet.SubnetId --output text
}
PUB_A=$(mk_subnet public-a <public-subnet-a-cidr> <availability-zone-a>); PUB_B=$(mk_subnet public-b <public-subnet-b-cidr> <availability-zone-b>)
PRIV_A=$(mk_subnet private-a <private-subnet-a-cidr> <availability-zone-a>); PRIV_B=$(mk_subnet private-b <private-subnet-b-cidr> <availability-zone-b>)
DATA_A=$(mk_subnet data-a <data-subnet-a-cidr> <availability-zone-a>); DATA_B=$(mk_subnet data-b <data-subnet-b-cidr> <availability-zone-b>)
```

Don't enable `map-public-ip-on-launch` broadly; assign EIPs explicitly to the few hosts that need them.

## IGW / NAT

```bash
IGW=$(aws ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW"
PUB_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$PUB_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW"
for s in "$PUB_A" "$PUB_B"; do aws ec2 associate-route-table --route-table-id "$PUB_RT" --subnet-id "$s"; done

# One NAT GW per AZ for HA (prod); a single NAT for dev to save cost
EIP_A=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
NAT_A=$(aws ec2 create-nat-gateway --subnet-id "$PUB_A" --allocation-id "$EIP_A" --query NatGateway.NatGatewayId --output text)
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_A"
PRIV_RT_A=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "$PRIV_RT_A" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_A"
aws ec2 associate-route-table --route-table-id "$PRIV_RT_A" --subnet-id "$PRIV_A"
# repeat for AZ b; data subnets get a route table with no 0.0.0.0/0
```

NAT Gateway is billed hourly and per GB. S3/DynamoDB gateway endpoints can reduce processing charges; compare supported regional options before choosing a topology.

## Security groups

Stateful; reference SGs instead of CIDRs inside the VPC.

```bash
mk_sg() { aws ec2 create-security-group --group-name "$1" --description "$2" --vpc-id "$VPC_ID" --query GroupId --output text; }
ALB_SG=$(mk_sg alb "public ALB");  APP_SG=$(mk_sg app "app tier");  DB_SG=$(mk_sg db "db tier")
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 443 --cidr <approved-public-source-cidr>
aws ec2 authorize-security-group-ingress --group-id "$APP_SG" --protocol tcp --port 8080 --source-group "$ALB_SG"
aws ec2 authorize-security-group-ingress --group-id "$DB_SG"  --protocol tcp --port 5432 --source-group "$APP_SG"

# Add only the protocol/port ranges and source networks supplied for the application.
```

Do not use broad ingress rules as a shortcut for application routing. Remove unused default security-group rules and audit with `aws ec2 describe-security-group-rules --filters Name=group-id,Values=<sg>`.

## NACLs

Stateless, subnet-level, numbered rules. Use sparingly (e.g. block known-bad CIDRs); if used, allow required ephemeral return ports and both directions for applicable protocols.

## VPC endpoints

```bash
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name "com.amazonaws.${AWS_REGION}.s3" \
  --route-table-ids "$PRIV_RT_A" <priv-rt-b>          # gateway, free
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --vpc-endpoint-type Interface \
  --service-name "com.amazonaws.${AWS_REGION}.secretsmanager" --subnet-ids "$PRIV_A" "$PRIV_B" \
  --security-group-ids <endpoint-sg> --private-dns-enabled   # hourly + per-GB
```

Typical interface set for private-only hosts: `ssm`, `ssmmessages`, `ec2messages`, `logs`, `secretsmanager`, `kms`, `ecr.api`, `ecr.dkr`, `sts`. Attach endpoint policies to restrict to your accounts/buckets.

## Flow logs

```bash
aws ec2 create-flow-log --resource-type VPC --resource-ids "$VPC_ID" --traffic-type ALL \
  --log-destination-type s3 --log-destination arn:aws:s3:::<flow-log-bucket>/vpc/ \
  --max-aggregation-interval 60 --log-format '${version} ${vpc-id} ${subnet-id} ${instance-id} ${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${packets} ${bytes} ${action} ${tcp-flags} ${pkt-srcaddr} ${pkt-dstaddr}'
```

S3 (+ Athena) is cheaper than CloudWatch Logs for retention; CloudWatch for live alerting. Forward to the organization-approved audit sink if required.

## Peering / Transit Gateway

- Peering: non-transitive, no overlapping CIDRs; add routes on **both** sides and SG rules referencing peer CIDR/SG.
  `aws ec2 create-vpc-peering-connection --vpc-id <a> --peer-vpc-id <b> --peer-owner-id <peer-account-id> --peer-region <r>` then `accept-vpc-peering-connection` from the peer.
- Multiple VPCs or hybrid networks: evaluate Transit Gateway and supported VPN/direct-connect options.

## Terraform/OpenTofu

For standard layouts, pin `terraform-aws-modules/vpc/aws` to `6.7.3` (checked 2026-10-28):

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"   # checked 2026-10-28
  name    = "${var.env}-vpc"
  cidr    = var.vpc_cidr
  azs              = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs
  enable_nat_gateway     = true
  one_nat_gateway_per_az = var.env == "prod"
  single_nat_gateway     = var.env != "prod"
  enable_flow_log        = true
  manage_default_security_group = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}
```

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| Private subnet no internet | NAT route in the subnet's RT; NAT in a public subnet with IGW route |
| Can't reach S3 privately | gateway endpoint on the right RTs; bucket policy `aws:SourceVpce` |
| SG rule ineffective | rule on the destination's SG; SG is stateful, NACL is not |
| One-way peering | routes/SGs missing on one side |
| Private DNS fails | `enableDnsSupport` + `enableDnsHostnames`; endpoint `private-dns-enabled` |
| Diagnose path | `aws ec2 create-network-insights-path` + `start-network-insights-analysis` (Reachability Analyzer) |
