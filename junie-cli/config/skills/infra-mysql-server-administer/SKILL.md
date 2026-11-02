---
name: infra-mysql-server-administer
description: "Administer MySQL or MariaDB servers: secure installation, credentials, grants, InnoDB tuning, GTID replication, monitoring, and online DDL. Use when tasks mention MySQL, MariaDB, mysqld, mysql client, InnoDB, GTID, replication source, or MySQL schema migrations."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/mysql
  license: MIT
---

# MySQL server administer

Operate self-managed MySQL or MariaDB with private networking, least-privilege accounts, and tested recovery paths.

## Triggers

- MySQL/MariaDB installation, configuration, authentication, grants, or tuning
- InnoDB workload, slow queries, lock waits, or capacity diagnosis
- GTID replication, replication errors, or online schema changes

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or database README if present
IF task involves MySQL/MariaDB administration, monitoring, replication, or migrations
  REFERENCE "references/mysql.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Identify product/version, host or managed-service role, workload, and current replication state.
2. Read current settings and diagnostics before changing configuration; prefer `SET PERSIST` only when supported and document persistence/restart behavior.
3. Use a dedicated migration/owner identity; prefer online DDL with explicit algorithm and lock clauses, and verify a restorable backup before destructive changes.
4. Apply only an approved change, monitor replication and lock behavior, then verify the original symptom and report rollback steps.

## Safety

- Pull credentials from Secret Manager or protected files; never put passwords in CLI arguments, source files, logs, or chat.
- Bind to private interfaces, require TLS where supported, and avoid wildcard account hosts or global grants.
- Do not kill sessions, skip replication errors, or run destructive DDL without explicit approval.

## Related skills

- PostgreSQL, MongoDB, and Redis administration: sibling database skills
- Managed Cloud SQL settings: `infra-gcp-cloudSql-manage`
- Backup and restore: `infra-any-backupRecovery-manage`
- Metrics and database alerting: `infra-prometheus-metrics-manage`

## References

- [MySQL and MariaDB administration](references/mysql.md)
