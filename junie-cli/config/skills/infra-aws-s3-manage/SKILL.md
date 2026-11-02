---
name: infra-aws-s3-manage
description: "Create and manage Amazon S3 buckets, access policies, encryption, versioning, lifecycle, replication, presigned URLs, and transfers. Use when requests mention S3, bucket policy, Block Public Access, object lock, lifecycle, replication, presigned URL, or S3 sync."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-s3
  license: MIT
---

# AWS S3 manage

Use this skill for S3 bucket and object-storage configuration. Treat public access, retention, replication, and bulk deletion as data-security decisions.

## Triggers

- Create or secure a bucket, policy, encryption configuration, versioning, or Object Lock.
- Configure lifecycle transitions, cross-region replication, or presigned access.
- Plan or troubleshoot bulk transfers and S3 data access.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-s3.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-s3.toml"
ELSE use the defaults listed below
IF task involves S3 buckets, policies, lifecycle, replication, or object access
  REFERENCE "references/s3.md"
CACHE only the loaded S3 guidance for this task
```

## Workflow

1. Confirm account, region, data owner, retention, access pattern, and IaC ownership before proposing changes.
2. Default to Terraform/OpenTofu; keep Block Public Access enabled, ACLs disabled, encryption and versioning enabled where appropriate, and TLS enforced.
3. Review bucket, identity, endpoint, and KMS policies together. Test access changes against intended principals and preserve a recovery path.
4. Treat lifecycle expiration, Object Lock retention, replication deletion behavior, and recursive transfers as destructive or irreversible; dry-run/list targets first and obtain explicit confirmation.
5. Verify policy status, encryption, versioning, replication health, lifecycle scope, and access without exposing object contents or bearer URLs.

### Defaults when no config exists

- IaC changes: Terraform/OpenTofu; AWS CLI read-only queries for inventory. Use DataSync or Batch Operations for sustained/large transfers.
- Keep buckets private by default and avoid account/site values in examples.
- Ask for bucket, region, prefixes, retention, principals, and KMS key selection when absent.

## Related skills

- AWS permissions → `infra-aws-iam-manage`
- VPC endpoints and private routing → `infra-aws-vpc-manage`
- Secret and key management → `sec-secrets-any-manage`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
