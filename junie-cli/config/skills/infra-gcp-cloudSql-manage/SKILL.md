---
name: infra-gcp-cloudSql-manage
description: "Manage Cloud SQL for PostgreSQL with gcloud: private IP, Private Services Access, IAM database authentication, Cloud SQL Auth Proxy, HA, replicas, backups, and PITR. Use when tasks mention Cloud SQL, cloud-sql-proxy, SQL instance connectivity, PostgreSQL on GCP, or Cloud SQL backup/restore."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/gcp-cloud-sql
  license: MIT
---

# GCP Cloud SQL manage

Operate Cloud SQL PostgreSQL with private networking, encrypted transport, least-privilege IAM, and recoverable change paths.

## Triggers

- Cloud SQL instance, PostgreSQL on GCP, Private Services Access (PSA), Private Service Connect (PSC)
- `cloud-sql-proxy`, IAM database auth, read replica, PITR, backup/restore, SQL flags

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves Cloud SQL provisioning, connectivity, operations, backups, or restore
  REFERENCE "references/cloud-sql.md"
IF the service is managed by Terraform or OpenTofu
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
IF the task crosses VPC, subnet, or private egress design
  REFERENCE skill "infra-gcp-vpc-manage"
CACHE project, region, VPC, database major, and maintenance window as runtime inputs
```

## Workflow

1. Confirm project, environment, instance ownership, database version compatibility, and required recovery point.
2. Inspect the instance, operation history, private path, TLS mode, and existing flags before changing anything.
3. Prefer private connectivity, IAM database authentication, and a proxy/connector; avoid public authorized networks.
4. Keep secrets in Secret Manager and grant access at the narrowest supported scope; do not place values in CLI arguments or state.
5. Treat replica promotion, restore, import, deletion, and flag changes that restart an instance as high-impact; require explicit approval.
6. Verify connection, health, logs, backup status, and application behavior after a change.

## Related skills

- `infra-gcp-vpc-manage` — private networking and service access.
- `infra-gcp-bigquery-manage` — BigQuery federation and analytics access.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — managed configuration.
- `sec-secrets-any-manage` — secret storage and access policy.
