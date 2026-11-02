---
name: infra-terraform-aws-manage
description: "Create, review, and troubleshoot Terraform HCL for AWS using `hashicorp/aws`, role assumption, VPC, EC2, security groups, RDS, and Secrets Manager. Use when requests mention Terraform plus AWS, `aws_*` resources, AWS provider configuration, or AWS-hosted infrastructure."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/terraform-aws
  license: MIT
---

# Terraform AWS provider manage

Provider-specific HCL patterns for AWS. Use the generic Terraform core skill for module design, state, tests, and CI.

## Triggers

- Terraform with AWS, `hashicorp/aws`, `aws_*` resources
- IAM role assumption, VPC, EC2, security group, RDS, S3 backend, Secrets Manager

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or infrastructure README if present
IF task uses AWS provider resources or authentication
  REFERENCE "references/aws-provider.md"
  REFERENCE "assets/provider.aws.tf"
IF task needs generic Terraform state, module, test, or CI guidance
  REFERENCE skill "infra-terraform-any-manage"
IF task uses OpenTofu commands or encryption
  REFERENCE skill "infra-opentofu-any-manage"
IF the request concerns AWS service operations rather than HCL
  REFERENCE the matching infra-aws-* service skill
CACHE account, region, role, backend, and provider lockfile versions
```

## Workflow

1. Confirm account, assumed role, region, backend, environment, and IaC ownership.
2. Use SSO or workload identity/OIDC role assumption; keep static access keys out of HCL and tfvars.
3. Use private subnets where possible, IMDSv2, encrypted storage, resource-scoped IAM, and managed secrets.
4. Treat CIDRs, availability zones, IDs, peer ranges, capacity, and names as explicit inputs.
5. Run `terraform fmt -check`, `terraform validate`, and a saved plan; review replacements, public paths, IAM, and data lifecycle.
6. Require approval for production applies, state changes, RDS failover, deletion, or key policy changes.

## Related skills

- `infra-terraform-any-manage` — shared Terraform workflow, state, testing, and CI.
- `infra-terraform-gcp-manage` / `infra-terraform-azure-manage` — other provider HCL.
- `infra-opentofu-any-manage` / `infra-opentofu-migration-run` — OpenTofu runtime and migration.
- `sec-dev-threatModel-create` — threat-model cross-account and public-edge changes.
