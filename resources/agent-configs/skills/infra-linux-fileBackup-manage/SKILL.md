---
name: infra-linux-fileBackup-manage
description: "Design and operate Linux file backups with encrypted, versioned repositories or controlled file synchronization, including restic, rsync, systemd timers, freshness alerts, and restore drills. Use when asked about Linux file backup, restic, rsync, file retention, backup timers, or file restore testing."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/storage/backup-recovery
  license: MIT
---

# Linux file backup and recovery

Choose a versioned encrypted backup when history and deduplication are needed; use synchronization only when a mirror is the intended outcome. Protect backups from compromise of the source host.

## Triggers

- Requests for Linux file backup, file restore, retention, backup automation, or restore drills.
- Work involving restic, rsync, systemd timers, backup freshness alerts, or off-host copies.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/linux-file-backup.md"
CACHE only the selected tool's configuration and safety checklist
```

## Workflow

1. Inventory files, ownership, consistency needs, exclusions, classification, recovery point, retention, and restore target.
2. Select restic for encrypted, deduplicated snapshot history or rsync for a deliberate mirror; define an independent destination and failure boundary.
3. Use a least-privilege backup identity, protected credentials, encryption, and a timer with persistent scheduling and restricted filesystem access.
4. Alert on job failure and on stale or missing snapshots; periodically run repository checks and restore into a new directory.
5. Validate permissions, ownership, ACLs, extended attributes, application consistency, and measured recovery time before closing the test.

## Safety

- Always preview rsync operations that use `--delete`; review the source, destination, and exact file changes before applying them.
- Preview restic retention/prune operations and require explicit authorization before deleting snapshots or repository data.
- Keep repository credentials and SSH keys out of scripts, command histories, logs, and skill documents.
- Pin a release only when a release binary is needed; verify its signature and checksum against the official release. The reference records the version checked for this draft.

## Related skills

- PostgreSQL, SQLite, and BigQuery recovery → `infra-postgresql-backup-manage`, `infra-sqlite-backup-manage`, `infra-bigquery-backup-manage`
- Cloud object storage and disk-snapshot configuration → `infra-gcp-any-manage`
- Storage resources as code → `infra-opentofu-any-manage` or `infra-terraform-any-manage`
- Recovery objectives and drills → `infra-ops-drPlan-create`
- Linux systemd timer administration → `infra-linux-systemd-manage`
- Recovery runbooks and incident handling → `docs-ops-runbook-create`, `sec-ops-incident-respond`
