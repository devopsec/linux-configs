---
name: infra-bigquery-backup-manage
description: "Plan and test BigQuery data recovery using time travel, table snapshots, exports, and dataset or table restoration. Use when a task mentions BigQuery backup, time travel, table snapshots, deleted-table recovery, BigQuery export, recovery windows, or BigQuery restore testing."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/database-backups
  license: MIT
---

# BigQuery backup and recovery

Match each recovery mechanism to the table's required recovery window, region, cost, and deletion risk. BigQuery time travel and fail-safe are not substitutes for an independent export or recovery plan.

## Triggers

- Requests for BigQuery backup, snapshot, time travel, export, restore, or deleted-table recovery.
- Recovery planning for datasets, partitioned tables, scheduled queries, or ingestion pipelines.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/bigquery-backup.md"
CACHE only the applicable recovery window, mechanism, and validation steps
```

## Workflow

1. Identify project, dataset, table, region, data owner, data sensitivity, retention/erasure rules, and approved RPO/RTO.
2. Check the configured time-travel window and use it for short-window table recovery; use snapshots or exports for longer retention and independent recovery.
3. Store exports outside the primary failure boundary with separate permissions, encryption, and retention controls.
4. Restore to a new table or dataset first. Validate schema, partitioning, row counts, representative queries, access controls, and downstream consumers.
5. Record source snapshot/export time, restore actions, cost/retention considerations, validation results, and measured recovery time.

## Safety

- A copy operation onto a live table can replace data. Prefer a new target and do not use force/replace flags without explicit approval.
- Time-travel and fail-safe windows and costs are service settings; check the current official BigQuery documentation and the actual dataset configuration before promising recovery.
- Treat personal or regulated data in snapshots and exports under the same access, retention, and erasure rules as the primary data.

## Related skills

- Database backups → `infra-postgresql-backup-manage` and `infra-sqlite-backup-manage`
- File and off-site backup targets → `infra-linux-fileBackup-manage`
- Recovery objectives and drills → `infra-ops-drPlan-create`
- GCS bucket policies and cross-region dataset configuration → `infra-gcp-any-manage`
