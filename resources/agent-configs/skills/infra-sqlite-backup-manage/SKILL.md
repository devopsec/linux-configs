---
name: infra-sqlite-backup-manage
description: "Create consistent SQLite backups, check integrity, and restore or rebuild embedded databases safely, including databases using WAL mode and derived config caches. Use when asked about SQLite backup, online backup, VACUUM INTO, integrity_check, WAL recovery, config.db, or a corrupt embedded database."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/database-backups
  license: MIT
---

# SQLite backup and recovery

Use SQLite's online backup API or `VACUUM INTO` for a live database. A raw file copy can be inconsistent when a writer is active or WAL files are involved.

## Triggers

- Requests to back up, verify, restore, or recover an SQLite database.
- Corruption reports, database migration, WAL/journal questions, or embedded-database recovery.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/sqlite-backup.md"
CACHE only the applicable consistency, verification, and recovery steps
```

## Workflow

1. Determine whether the SQLite database is a source of truth or a rebuildable cache; identify its writer and maintenance window.
2. Use `.backup` or `VACUUM INTO` to take a consistent copy; do not copy a live database and its `-wal`/`-shm` files independently.
3. Restrict backup permissions, protect off-host copies, and record timestamps and checksums where appropriate.
4. Run `PRAGMA integrity_check` against the copy and compare application-level invariants or representative row counts.
5. Restore into a new path first, stop writers before replacement, set expected ownership and permissions, and verify the application can reopen the database.

## Safety

- Do not overwrite or remove the only known-good database during recovery. Preserve a forensic copy when corruption or an incident is suspected.
- Treat restore-over-live and cleanup of historical copies as destructive; require approval and an independent recovery copy.
- Rebuild a derived database from its authoritative source when that is safer and quicker than restoring an old cache.

## Related skills

- PostgreSQL source-of-truth recovery → `infra-postgresql-backup-manage`
- Linux file-level backups → `infra-linux-fileBackup-manage`
- Recovery objectives and restore exercises → `infra-ops-drPlan-create`
- BigQuery protection → `infra-bigquery-backup-manage`
