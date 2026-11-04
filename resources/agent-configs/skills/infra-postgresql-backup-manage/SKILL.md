---
name: infra-postgresql-backup-manage
description: "Design, operate, and test PostgreSQL and Cloud SQL backups and restores, including logical dumps, physical base backups, WAL archiving, point-in-time recovery, retention, and restore drills. Use when a task mentions PostgreSQL backup, Cloud SQL backup, pg_dump, pg_basebackup, WAL, PITR clone, pgBackRest, WAL-G, database restore, or PostgreSQL recovery objectives."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/database-backups
  license: MIT
---

# PostgreSQL backup and recovery

Plan PostgreSQL protection around recoverability and the declared RPO/RTO. Choose the managed service or self-managed procedure for the actual deployment; keep provider-specific settings outside this database-focused workflow.

## Triggers

- Requests for PostgreSQL or Cloud SQL backups, restore testing, retention, PITR, WAL archiving, or recovery planning.
- Work involving `pg_dump`, `pg_restore`, `pg_basebackup`, pgBackRest, or WAL-G.
- Database migrations or risky changes that require a verified recovery point.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/postgresql-backup.md"
CACHE only the applicable backup and restore procedure
```

## Workflow

1. Confirm database ownership, deployment type, data classification, approved RPO/RTO, retention, and recovery target.
2. For Cloud SQL, verify automated backups/PITR and approved off-project logical exports; for self-managed PostgreSQL, choose logical dumps for portability or physical backups plus continuous WAL archiving for PITR/scale needs.
3. Configure least-privilege backup identities, encrypted off-host storage, retention, and alerts for both job failure and stale backups.
4. Restore into a new instance or database first. Use a compatible server version and required extensions; validate schema, roles, representative queries, and application compatibility.
5. Record backup time, restore point, integrity checks, elapsed recovery time, exceptions, and the next test date.

## Safety

- Keep credentials out of command arguments, logs, skill files, and reports; use a protected credential file or approved credential manager.
- Treat `pg_restore --clean`, overwriting a production target, and deleting backup history as destructive. Require explicit approval and a fresh verified recovery point.
- A successful backup command is not proof of a recoverable database; schedule and document restore drills.

## Related skills

- File-level and off-host copies → `infra-linux-fileBackup-manage`
- GCP Cloud SQL instance administration → `infra-gcp-any-manage`
- Recovery objectives and failover planning → `infra-ops-drPlan-create`
- SQLite recovery → `infra-sqlite-backup-manage`
- BigQuery recovery → `infra-bigquery-backup-manage`
- Framework retention/evidence requirements → the relevant `sec-*-framework-assess` skill
- Recovery runbook and incident procedures → `docs-ops-runbook-create`, `sec-ops-incident-respond`
