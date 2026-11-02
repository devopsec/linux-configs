---
name: infra-aws-cloudformation-manage
description: "Author, validate, deploy, and troubleshoot AWS CloudFormation templates, stacks, change sets, StackSets, drift, and nested stacks with AWS CLI and cfn-lint. Use when requests mention CloudFormation, change sets, StackSets, drift detection, stack policy, SAM templates, or cfn-lint."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/cloudformation
  license: MIT
---

# AWS CloudFormation manage

Use CloudFormation when the workload requires AWS-native stack features or already has CloudFormation ownership; do not manage one resource from multiple IaC systems.

## Triggers

- Create, validate, update, or troubleshoot a CloudFormation template or stack.
- Review change sets, stack drift, nested stacks, StackSets, or rollback failures.
- Use CloudFormation for SAM, Control Tower, Service Catalog, or third-party templates.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-cloudformation.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-cloudformation.toml"
ELSE use the defaults listed below
IF task involves CloudFormation templates, stacks, change sets, StackSets, or drift
  REFERENCE "references/cloudformation.md"
CACHE only the loaded CloudFormation guidance for this task
```

## Workflow

1. Establish account, region, stack ownership, template source, and deployment environment read-only.
2. Lint with cfn-lint and run CloudFormation template validation. Pin cfn-lint `1.58.0` (checked 2026-10-28) in the tooling environment; do not install through a shell-piped download.
3. Produce a change set and inspect every replacement, deletion, IAM capability, retained resource, and stateful-resource effect.
4. Obtain explicit confirmation for executing a change set with destructive or production impact. Preserve snapshots/retention and termination protection for stateful stacks.
5. Execute only the reviewed change set; wait for completion, inspect events and drift, and document rollback steps.

### Defaults when no config exists

- IaC: Terraform/OpenTofu by default; choose CloudFormation only when its AWS-native integrations or existing ownership require it.
- Validation: cfn-lint `1.58.0` and AWS CLI CloudFormation validation (checked 2026-10-28).
- Ask for account, region, stack name, deployment window, and data-retention requirements when missing.

## Related skills

- AWS service semantics → `infra-aws-ec2-manage`, `infra-aws-s3-manage`, `infra-aws-lambda-manage`, `infra-aws-rds-manage`
- IaC decision and Terraform/OpenTofu workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
- IAM capabilities and roles → `infra-aws-iam-manage`
