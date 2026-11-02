# AWS EC2 — instances, launch templates, ASG, AMIs

## Contents
- Instance type selection
- Launch (IMDSv2, encrypted gp3)
- User data (RHEL-family / AL2023)
- Launch templates + Auto Scaling
- Spot
- AMIs
- Day-2 operations and metadata
- Terraform/OpenTofu
- Troubleshooting

## Instance type selection

| Category | Families | Use |
|---|---|---|
| General | t3/t3a (burstable), m7i, m7g/m8g (Graviton) | web, small DBs, dev |
| Compute | c7i, c7g/c8g | compute-bound services, media processing, batch |
| Memory | r7i, r7g/r8g | caches, large PostgreSQL |
| Storage | i4i, d3 | local NVMe, warehouses |
| Accelerated | g5/g6, p5, inf2 | ML |

Graviton (`*g`) may reduce cost; validate application and package compatibility on ARM before rollout. Burstable families are best suited to workloads with intermittent CPU use.

## Launch an instance

```bash
aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type c7i.large \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${SG_ID}" \
  --iam-instance-profile Name=<app-instance-profile> \
  --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3","Encrypted":true}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=<name>},{Key=Environment,Value=<env>}]' \
  --user-data file://userdata.sh
```

- Always `HttpTokens=required` (IMDSv2). Hop limit 1, or 2 when containers on the host need IMDS.
- Prefer SSM Session Manager over SSH keys; if keys are needed, import a public key (`aws ec2 import-key-pair --public-key-material fileb://<public-key-file>`) rather than letting AWS generate and you store the private key.
- Resolve the approved OS image to an immutable AMI ID before production rollout; an SSM public image alias may change over time.
  For golden images build with Packer (`infra-packer-awsAmi-build`).

## User data (AL2023 / RHEL-family)

```bash
#!/usr/bin/env bash
set -euo pipefail
dnf -y update
dnf -y install amazon-cloudwatch-agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:AmazonCloudWatch-linux
# Install required application packages through the chosen configuration-management method.
systemctl enable --now <service>.service
```

- CodeDeploy agent (only if used): prefer SSM Distributor `AWSCodeDeployAgent`. If a package is required, choose a pinned release and verify its signature before installation; do not run an upstream install script.
- Logs: `/var/log/cloud-init-output.log`. SELinux stays enforcing; label custom paths with `semanage fcontext` + `restorecon`.

## Launch template + Auto Scaling

```bash
aws ec2 create-launch-template --launch-template-name <app>-lt \
  --launch-template-data file://lt-data.json   # ImageId, InstanceType, IamInstanceProfile, MetadataOptions.HttpTokens=required, encrypted gp3, UserData (base64)
aws ec2 create-launch-template-version --launch-template-name <app>-lt --source-version 1 \
  --launch-template-data '{"ImageId":"<new-ami-id>"}'
aws ec2 modify-launch-template --launch-template-name <app>-lt --default-version 2

aws autoscaling create-auto-scaling-group --auto-scaling-group-name <app>-asg \
  --mixed-instances-policy file://mixed.json \
  --min-size 2 --max-size 10 --desired-capacity 2 \
  --vpc-zone-identifier "<subnet-a>,<subnet-b>" \
  --target-group-arns "<target-group-arn>" \
  --health-check-type ELB --health-check-grace-period 300

aws autoscaling put-scaling-policy --auto-scaling-group-name <app>-asg \
  --policy-name cpu-60 --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{"PredefinedMetricSpecification":{"PredefinedMetricType":"ASGAverageCPUUtilization"},"TargetValue":60}'

# Roll new AMI out safely
aws autoscaling start-instance-refresh --auto-scaling-group-name <app>-asg \
  --preferences '{"MinHealthyPercentage":90,"InstanceWarmup":300}'
```

`mixed.json`: `LaunchTemplateSpecification` + `Overrides` (3+ instance types) + `InstancesDistribution` (`OnDemandBaseCapacity`, `OnDemandPercentageAboveBaseCapacity`, `SpotAllocationStrategy: price-capacity-optimized`).
Stateful applications should use lifecycle hooks to drain work before scale-in.

## Spot

- Use ASG mixed instances or EC2 Fleet with `price-capacity-optimized`; diversify types and AZs. Legacy `request-spot-instances`/Spot Fleet with a max price is discouraged.
- 2-minute interruption notice via EventBridge (`EC2 Spot Instance Interruption Warning`) — handle drain there.
- Avoid Spot for stateful or interruption-sensitive workloads unless disruption is handled by the application.

## AMIs

```bash
aws ec2 create-image --instance-id <i-id> --name "<app>-$(date +%Y%m%d)" --no-reboot   # --no-reboot = crash-consistent only
aws ec2 copy-image --source-image-id <ami-id> --source-region <src> --region <dr-region> --name <name> --encrypted
aws ec2 modify-image-attribute --image-id <ami-id> --launch-permission "Add=[{UserId=<target-account-id>}]"
# DESTRUCTIVE (gated): list first, then deregister + delete snapshots
aws ec2 describe-images --owners self --query 'Images[?CreationDate<`<yyyy-mm-dd>`].[ImageId,Name]' --output table
aws ec2 deregister-image --image-id <ami-id> --dry-run
```

Prefer EC2 Image Builder or Packer pipelines; enable AMI deprecation (`enable-image-deprecation`) and Recycle Bin retention rules. Resolve mutable image aliases to an approved AMI ID before production rollout.

## Day-2 operations

```bash
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,IP:PrivateIpAddress,Name:Tags[?Key=='Name']|[0].Value}" --output table
aws ec2 stop-instances --instance-ids <i-id> && aws ec2 wait instance-stopped --instance-ids <i-id>
aws ec2 modify-instance-attribute --instance-id <i-id> --instance-type '{"Value":"c7i.xlarge"}'
aws ec2 start-instances --instance-ids <i-id>
aws ec2 get-console-output --instance-id <i-id> --latest --output text
aws ssm start-session --target <i-id>
# DESTRUCTIVE: aws ec2 terminate-instances --instance-ids <i-id>   (enable --disable-api-termination on prod)
```

Instance metadata from inside the host: use `ec2-metadata` (package `amazon-ec2-utils`, e.g. `ec2-metadata --instance-id`) or the SDK's IMDS client — both handle the IMDSv2 token. Never log credential responses.

## Terraform/OpenTofu

```hcl
resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = var.approved_ami_id
  instance_type = var.instance_type
  iam_instance_profile { name = aws_iam_instance_profile.app.name }
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }
  user_data = base64encode(file("${path.module}/userdata.sh"))
}

resource "aws_autoscaling_group" "app" {
  min_size            = 2
  max_size            = 10
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }
  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 90 }
  }
}
```

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| `InsufficientInstanceCapacity` / stuck pending | other AZ or instance type; diversify ASG overrides |
| Cannot connect | SG + NACL + route table; prefer SSM (needs `AmazonSSMManagedInstanceCore` + endpoint/NAT) |
| Terminates immediately | `describe-instances` → `StateReason` (KMS key policy, EBS limits) |
| User data not running | shebang, base64 in LT, `/var/log/cloud-init-output.log` |
| ASG kills booting nodes | raise health-check grace period |
| gp2 IOPS ceiling | migrate to gp3 (`modify-volume`), set IOPS/throughput |
| Packet loss or throughput limits | enhanced networking (ENA), suitable instance size, check security-group and route policy |
