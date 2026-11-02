---
name: infra-aws-iam-manage
description: "Manage AWS IAM identities, roles, policies, permission boundaries, STS role sessions, and OIDC federation using AWS CLI and Terraform/OpenTofu. Use when requests mention IAM, AssumeRole, AccessDenied, IAM policy, OIDC, workload identity, service roles, SCPs, or Access Analyzer."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-iam
  license: MIT
---

# AWS IAM manage

Use this skill for AWS identity and authorization. Prefer short-lived role credentials and narrowly scoped permissions over IAM users or long-lived keys.

## Triggers

- Create or troubleshoot IAM roles, trust policies, permission policies, or access boundaries.
- Configure STS cross-account access or OIDC federation for CI.
- Investigate `AccessDenied`, unused access, or policy validation findings.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-iam.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-iam.toml"
ELSE use the defaults listed below
IF task involves AWS IAM roles, policies, federation, or access analysis
  REFERENCE "references/iam.md"
CACHE only the loaded IAM guidance for this task
```

## Workflow

1. Establish caller identity, account, and target role read-only; confirm the target account and trust relationship with the user.
2. Prefer Terraform/OpenTofu for managed policy changes. Use AWS CLI for read-only diagnosis and AWS Access Analyzer policy validation.
3. Scope actions and resources narrowly; add conditions where supported. Review the full effective permission path, including explicit denies, boundaries, SCPs, session policies, and resource policies.
4. For federation, constrain issuer, audience, and subject to the exact workload. Never recommend stored access keys or broad wildcard trust.
5. Apply only after reviewing the plan and obtaining confirmation for privilege increases; test the intended identity and action without printing tokens or credentials.

### Defaults when no config exists

- IaC changes: Terraform/OpenTofu; diagnosis: AWS CLI read-only queries and IAM Access Analyzer.
- Use IAM Identity Center for humans and short-lived role sessions for workloads; avoid IAM users and long-lived credentials.
- Ask for account, principal, resource scope, and expected actions when missing.

## Related skills

- Service-specific AWS permissions → `infra-aws-ec2-manage`, `infra-aws-lambda-manage`, `infra-aws-s3-manage`
- Secrets lifecycle → `sec-secrets-any-manage`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
- Security threat analysis → `sec-dev-threatModel-create`
