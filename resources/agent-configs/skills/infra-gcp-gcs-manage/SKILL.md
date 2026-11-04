---
name: infra-gcp-gcs-manage
description: "Manage Google Cloud Storage buckets, object IAM, lifecycle, versioning, retention, encryption, and transfers. Use when a task mentions `gs://`, gcloud storage, bucket policy, signed URLs, object generations, lifecycle rules, or GCS notifications."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/storage/object-storage]
  license: MIT
---

# Google Cloud Storage management

## Triggers

- Create or secure a GCS bucket, set object access, or configure encryption.
- Manage object versions, soft delete, retention, lifecycle, signed URLs, or transfer operations.
- Diagnose access, location, or storage-cost issues for `gs://` objects.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or cloud operations policy if present
REFERENCE "references/gcs.md"
IF the bucket or IAM is declared in OpenTofu/Terraform
  REFERENCE the matching IaC skill and inspect state/plan before live changes
IF task requires S3-compatible clients
  REFERENCE the GCS XML API compatibility notes; do not switch to AWS S3 administration
CACHE only the bucket, IAM, lifecycle, or transfer guidance needed
```

## Workflow

1. Confirm project, bucket, region, owner, data class, data-retention requirements, and whether the bucket is IaC-managed.
2. Inspect bucket configuration, IAM, versioning, soft-delete policy, encryption, and lifecycle before proposing a change.
3. Prefer uniform bucket-level access, public access prevention, workload identity/ADC, and narrowly scoped object roles.
4. Dry-run and list object operations; stage lifecycle changes and confirm irreversible retention locks separately.
5. Verify access with the intended principal and record effective policy and recovery behavior.

## Safety

- Never put service-account keys, HMAC secrets, or signed URLs in files, output, or logs.
- Treat recursive deletes and retention-policy locks as destructive; require explicit approval and verify recovery protection.
- Do not grant `allUsers` access unless public access is explicitly required and approved.

## Related skills

- Storage backup and recovery → `infra-any-backupRecovery-manage`
- GCP IAM and KMS → `infra-gcp-any-manage`, `sec-secrets-any-manage`
- S3 bucket operations → `infra-aws-s3-manage`
- CDN and static origins → `infra-network-cdn-manage`

## References

- [references/gcs.md](references/gcs.md) — secure buckets, IAM, lifecycle, encryption, object operations, and S3-compatible access boundary.
