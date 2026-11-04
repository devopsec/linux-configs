---
name: infra-postgresql-server-administer
description: "Administer PostgreSQL servers on Linux or Cloud SQL: configuration, pg_hba authentication, roles and grants, streaming/logical replication, PgBouncer, diagnostics, vacuum, partitions, and safe schema changes. Use when a task mentions PostgreSQL, Postgres, psql, pg_dump, pg_hba.conf, PgBouncer, autovacuum, replication lag, locks, slow queries, pg_stat_statements, or PostgreSQL upgrades."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/postgresql
  license: MIT
---

# PostgreSQL server administer

Administer PostgreSQL on self-managed Linux hosts and managed services. Prefer read-only diagnosis, least-privilege roles, online changes, and a verifiable rollback.

## Triggers

- PostgreSQL installation, configuration, authentication, roles, or grants
- Replication, PgBouncer, connection exhaustion, or major-version upgrades
- Slow queries, locks, vacuum, bloat, partitions, or `pg_cron`
- Live schema migrations, index changes, or backfills

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or database README if present
IF task involves server configuration, pg_hba, roles, grants, replication, or PgBouncer
  REFERENCE "references/postgresql-admin.md"
IF task involves monitoring, query diagnostics, locks, vacuum, bloat, or partitions
  REFERENCE "references/postgresql-monitoring-maintenance.md"
IF task involves schema migrations or DDL on a live database
  REFERENCE "references/migrations-safety.md"
CACHE only the loaded reference summaries for this task
```

## Workflow

1. Identify the server major version, deployment type, role (primary/replica), and maintenance window. For Cloud SQL, manage instance flags and HA through the managed-service interface rather than editing host files.
2. Capture read-only diagnostics and effective settings before proposing changes; determine whether a setting needs reload or restart.
3. Check for a restorable backup before destructive or large changes. Set `lock_timeout` and `statement_timeout` for DDL; use expand/migrate/contract for app-compatible migrations.
4. Get explicit approval before destructive SQL, terminating sessions, or a production restart. Apply the smallest reversible change and verify with the original diagnostics.

## Safety

- Source credentials from Secret Manager or protected environment files; never put passwords in command history, files, URLs, or output.
- Bind network access to private interfaces and approved application subnets; prefer `scram-sha-256` or TLS client authentication.
- Keep application grants separate from schema-owner and migration roles. Avoid blocking maintenance on hot tables without a window.
- Report rollback, restart requirements, verification, and any remaining risk.

## Related skills

- MySQL, MongoDB, and Redis administration: sibling database skills
- Cloud SQL resources and IAM: `infra-gcp-cloudSql-manage`
- Backup/PITR and restore drills: `infra-any-backupRecovery-manage`
- Metrics and database alerting: `infra-prometheus-metrics-manage`
- Database schema changes in application code: `infra-terraform-any-manage` / `infra-opentofu-any-manage`

## References

- [PostgreSQL administration](references/postgresql-admin.md)
- [Monitoring and maintenance](references/postgresql-monitoring-maintenance.md)
- [Migration safety](references/migrations-safety.md)
