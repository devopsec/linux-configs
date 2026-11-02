# Provider: AWS (`hashicorp/aws`)

AWS-specific HCL only. Backend syntax/locking: [State Management](state-management.md#choosing-a-remote-backend); SG rule style and secrets: [Security & Compliance](security-compliance.md). Our primary cloud is GCP ([providers-gcp.md](providers-gcp.md)); use this for AWS-hosted peers/DR. Snippets valid for `terraform` and `tofu`.

Contents: [Provider & auth](#provider-and-auth) · [Network](#network-vpc-module) · [EC2](#ec2-sip-host) · [Security groups](#security-groups-siprtp) · [RDS PostgreSQL](#rds-postgresql) · [Gotchas](#gotchas)

## Provider and auth

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # 6.70.0 latest as of 2026-10; verify latest
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn     = var.deploy_role_arn
    session_name = "terraform"
  }

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}
```

- No `access_key`/`secret_key` in HCL or tfvars. Local: `aws sso login --profile <p>` + `AWS_PROFILE`; CI: OIDC federation to the role (GitHub `aws-actions/configure-aws-credentials`, GCP Cloud Build via web identity).
- Multi-region/account: aliased providers (`provider "aws" { alias = "dr" ... }`) passed to modules via `providers = { aws = aws.dr }`.
- S3 backend: `use_lockfile = true` (1.10+); DynamoDB locking is legacy.

## Network (VPC module)

Prefer the registry module over hand-rolled `count`-per-AZ VPCs (upstream asset dropped — index-based identity, see [Code Patterns](code-patterns.md#count-vs-for_each-deep-dive)).

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3" # latest as of 2026-10; pin exact in prod

  name            = "${var.name_prefix}-vpc"
  cidr            = "10.20.0.0/16"
  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24"]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
  enable_flow_log        = true
}
```

SIP edges sit in public subnets with an Elastic IP (1:1, no NAT gateway) — same advertise rule as on GCP.

## EC2 SIP host

```hcl
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat
  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
}

resource "aws_instance" "sip_edge" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "c7i.xlarge"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.sip_edge.id]
  iam_instance_profile   = var.instance_profile_name

  metadata_options {
    http_tokens   = "required" # IMDSv2 only
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 50
  }

  lifecycle {
    ignore_changes = [ami] # roll AMIs deliberately, not on every plan
  }
}

resource "aws_eip" "sip_edge" {
  instance = aws_instance.sip_edge.id
  domain   = "vpc"
}
```

## Security groups (SIP/RTP)

Separate rule resources (provider v5+), never inline `ingress` blocks.

```hcl
resource "aws_security_group" "sip_edge" {
  name   = "${var.name_prefix}-sip-edge"
  vpc_id = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "sip" {
  for_each = {
    for pair in setproduct(var.sip_peer_ranges, ["udp", "tcp"]) : "${pair[0]}-${pair[1]}" => pair
  }

  security_group_id = aws_security_group.sip_edge.id
  cidr_ipv4         = each.value[0]
  ip_protocol       = each.value[1]
  from_port         = 5060
  to_port           = 5060
}

resource "aws_vpc_security_group_ingress_rule" "sip_tls" {
  for_each = toset(var.sip_peer_ranges)

  security_group_id = aws_security_group.sip_edge.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5061
  to_port           = 5061
}

resource "aws_vpc_security_group_ingress_rule" "rtp" {
  for_each = toset(var.media_peer_ranges)

  security_group_id = aws_security_group.sip_edge.id
  cidr_ipv4         = each.value
  ip_protocol       = "udp"
  from_port         = var.rtp_port_min
  to_port           = var.rtp_port_max
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.sip_edge.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

SSH: use SSM Session Manager (no port 22 rule).

## RDS PostgreSQL

```hcl
resource "aws_db_instance" "pg" {
  identifier                          = "${var.name_prefix}-pg"
  engine                              = "postgres"
  engine_version                      = "17" # verify latest supported
  instance_class                      = "db.m7g.large"
  allocated_storage                   = 100
  storage_encrypted                   = true
  db_subnet_group_name                = var.db_subnet_group_name
  vpc_security_group_ids              = [var.db_sg_id]
  username                            = "isen_admin"
  manage_master_user_password         = true # password generated + rotated in Secrets Manager, not in state
  multi_az                            = true
  backup_retention_period             = 14
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name_prefix}-pg-final"
  iam_database_authentication_enabled = true
}
```

## Gotchas

| Gotcha | Fix |
|--------|-----|
| `default_tags` + identical resource `tags` → perpetual diff | Don't repeat default keys in `tags` |
| Inline `ingress` + rule resources on same SG | Fight each other — use rule resources only |
| `most_recent` AMI data source replaces instances | `ignore_changes = [ami]` or pin AMI ID |
| Provider 5 → 6 bump | Separate PR; read v6 upgrade guide; plan must show no replacements |
| NAT gateway in front of SIP | Breaks SIP addressing — EIP on the edge instead |
