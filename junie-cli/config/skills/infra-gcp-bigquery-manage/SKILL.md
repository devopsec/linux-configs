---
name: infra-gcp-bigquery-manage
description: "Manage BigQuery datasets, tables, query jobs, IAM, partitioning, clustering, reservations, retention, and cost controls with bq, SQL, and GCP tooling. Use when tasks mention BigQuery, `bq query`, dataset location, INFORMATION_SCHEMA.JOBS, partitioned tables, slot reservations, or BigQuery IAM."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: []
  license: MIT
---

# GCP BigQuery manage

In-house guidance for safe BigQuery dataset, table, query, access, and capacity operations. Data and billing are customer-controlled; inspect before changing.

## Triggers

- BigQuery dataset/table, `bq`, SQL job, `INFORMATION_SCHEMA.JOBS`
- Partitioning, clustering, dataset location, bytes billed, slots/reservations, dataset IAM

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves BigQuery datasets, tables, query cost, IAM, or job operations
  REFERENCE "references/bigquery-operations.md"
IF task involves event delivery or BigQuery subscriptions
  REFERENCE skill "infra-gcp-pubsub-manage"
IF task creates or changes BigQuery resources in HCL
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
CACHE project, billing project, location, data classification, and retention as runtime inputs
```

## Workflow

1. Confirm the project, billing identity, dataset location, data classification, retention, and expected query shape.
2. Inspect existing datasets, IAM, table partitioning, job history, and any data lifecycle constraints.
3. Preview SQL with dry-run and a bytes-billed cap; select only required fields and filter partitions early.
4. Use dataset/table-scoped IAM and separate job submission permission from data read/write permission.
5. Treat deletes, truncation, expiration changes, policy changes, and capacity commitments as high-impact; request approval.
6. Verify job completion, bytes processed, query plan, access logs, and downstream consumers.

## Stack notes

- BigQuery is a managed service; choose data location before creation and keep query jobs and referenced data location-compatible.
- For Cloud Build, follow generic identity separation: validation jobs should not write datasets, publisher/deployer identities are distinct, and release verification is read-only. Do not copy project IDs or service-account names into a global skill.
- Database and SQL client versions belong in the consuming project’s lockfile, not in this service-management guidance.

## Related skills

- `infra-gcp-pubsub-manage` — event ingestion and export subscriptions.
- `infra-gcp-cloudSql-manage` — PostgreSQL federation and source database connectivity.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — dataset and IAM IaC.
