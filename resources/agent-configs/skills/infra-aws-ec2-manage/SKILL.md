---
name: infra-aws-ec2-manage
description: "Manage Amazon EC2 instances, launch templates, Auto Scaling groups, AMIs, Spot capacity, and instance access with AWS CLI and Terraform/OpenTofu. Use when requests mention EC2, instance types, AMIs, launch templates, ASGs, Spot Instances, IMDSv2, EBS, SSM Session Manager, or EC2 scaling."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-ec2
  license: MIT
---

# AWS EC2 manage

Use this skill for Amazon EC2 compute lifecycle work; keep network, IAM, and image-building details with their specialist skills.

## Triggers

- Create, resize, patch, or troubleshoot an EC2 instance or Auto Scaling group.
- Design launch templates, AMIs, Spot capacity, or instance metadata access.
- Configure EBS on EC2 or connect through Systems Manager Session Manager.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-ec2.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-ec2.toml"
ELSE use the defaults listed below
IF task involves EC2 instances, launch templates, Auto Scaling, Spot, AMIs, or instance access
  REFERENCE "references/ec2.md"
CACHE only the loaded EC2 guidance for this task
```

## Workflow

1. Use the selected toolchain defaults below or the configured overrides. Inspect identity, account, region, and target resource read-only; confirm the intended environment with the user.
2. Check whether the resource is IaC-managed. Prefer a reviewed Terraform/OpenTofu plan; use AWS CLI for inspection and one-off operations only when appropriate.
3. Describe replacement, downtime, data-loss, and cost effects before applying. Require explicit confirmation naming account and environment for termination, AMI deregistration, or other destructive changes; snapshot first where possible.
4. Default to IMDSv2, encrypted EBS, private access, least-privilege instance profiles, and SSM Session Manager. Never expose credential material or secret values.
5. Verify instance and ASG health, rollout completion, alarms, and access after changes; document resource identifiers as placeholders.

### Defaults when no config exists

- IaC changes: Terraform/OpenTofu; use the AWS CLI for read-only inventory and verification.
- Golden-image creation: Packer (`infra-packer-awsAmi-build`); do not use user-data as a substitute for image lifecycle management.
- Ask for account, region, subnet, security group, image, size, and scaling constraints when they are not provided; do not invent site-specific values.

## Related skills

- Network placement and security groups → `infra-aws-vpc-manage`
- Instance roles and permissions → `infra-aws-iam-manage`
- Golden AMIs → `infra-packer-awsAmi-build`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
- Host access and operating-system hardening → `infra-linux-ssh-manage`, `sec-linux-host-harden`
