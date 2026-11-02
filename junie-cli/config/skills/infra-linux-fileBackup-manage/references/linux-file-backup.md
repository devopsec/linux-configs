# Linux file backup reference

## Select the mechanism and destination

| Mechanism | Prefer when | Important limitation |
|---|---|---|
| restic | Encrypted, deduplicated snapshots and retention history are needed | The repository needs a separate recovery credential and deletion/prune permissions; pruning removes history |
| rsync | A controlled file-tree mirror or transfer is needed | A mirror is not version history; `--delete` can remove destination data |
| Filesystem/cloud snapshot | Fast volume recovery is useful | Usually crash-consistent; coordinate database/application writes and test recovery |

Store offsite backups in a separately administered project/failure boundary where policy allows. Immutable dump/export buckets can use a retention policy or lock after policy approval; a restic repository that must prune needs delete capability and must not be blocked by a retention lock. Keep those use cases in separate buckets/identities. Do not assume versioning, soft-delete, and retention features are mutually exclusive; check the current Cloud Storage feature compatibility and restore semantics. Manage GCS bucket, key, and IAM resources through the dedicated cloud-storage/IaC skills.

Compute Engine disk snapshots are crash-consistent. Use database-native backup/PITR for database recovery; snapshots can shorten host rebuild time but do not establish a consistent database restore point.

## restic

Restic `0.19.1` was the most recent release found on 2026-10-28. On RHEL-family hosts use the approved package repository (for example, `dnf install restic`); on Debian-family hosts use the configured package manager. If a release binary is required, use the signed official release and verify its published signature and checksum against a trusted key before installation. No unverified installer pipeline.

On a Compute Engine VM, use its approved service identity/Application Default Credentials for GCS. Elsewhere, use an approved workload/service identity rather than copying a long-lived key. Example protected shell-environment settings (replace every placeholder from approved configuration; do not source as written):

```bash
BACKUP_BUCKET_ID='set-from-approved-config'
HOST_ID='set-from-approved-config'
BACKUP_PROJECT_ID='set-from-approved-config'
RESTIC_SECRET_NAME='set-from-approved-config'
RESTIC_REPOSITORY="gs:${BACKUP_BUCKET_ID}:/restic/${HOST_ID}"
GOOGLE_PROJECT_ID="$BACKUP_PROJECT_ID"
RESTIC_PASSWORD_COMMAND="gcloud secrets versions access latest --secret=$RESTIC_SECRET_NAME --project=$BACKUP_PROJECT_ID"
RESTIC_CACHE_DIR='/var/cache/restic'
```

Define those referenced values in the trusted wrapper/configuration. Keep the shell environment file root-owned and mode `0600`; never store the returned credential itself in the file. The backup identity needs list/read/write and delete on the repository prefix for pruning; separate routine backup access from maintenance/prune authority where practical.

```bash
set -a &&
. "$RESTIC_ENV_FILE" &&
set +a &&
restic backup "$SOURCE_DIR" --tag "$BACKUP_TAG" &&
restic snapshots --tag "$BACKUP_TAG"
```

Initialize only a new repository, after verifying the destination:

```bash
set -a &&
. "$RESTIC_ENV_FILE" &&
set +a &&
restic init
```

Schedule repository checks separately from routine backups:

```bash
set -a &&
. "$RESTIC_ENV_FILE" &&
set +a &&
restic check
```

Restore drills and retention previews are separate operations:

```bash
set -a &&
. "$RESTIC_ENV_FILE" &&
set +a &&
restic restore latest --target "$NEW_RESTORE_DIR"
```

Preview retention separately; the numbers are illustrative:

```bash
set -a &&
. "$RESTIC_ENV_FILE" &&
set +a &&
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --dry-run
```

The retention counts are illustrative, not defaults. Review the dry-run target and snapshots before the destructive `restic forget ... --prune` operation. Restore into a new directory and verify content, ownership, ACLs, extended attributes, and application consistency.

## rsync

Use rsync only when a mirror is intended; pair it with snapshots or a versioned repository if history is required. Preview deletion first:

```bash
rsync -aHAX --numeric-ids --dry-run --delete \
  --rsh="ssh -i $BACKUP_KEY -o IdentitiesOnly=yes" "$SOURCE_DIR" "$DESTINATION"
```

Review the exact source, destination, and file list before removing `--dry-run`; `--delete` is destructive. Protect the key (mode `0600`) and restrict the receiver to the approved backup path with a forced-command helper such as `rrsync` and SSH restrictions. For hard-link incrementals, use a reviewed `--link-dest` to the previous tree and rotate only after previewing the exact target set.

## systemd scheduling and monitoring

- Use a restricted one-shot systemd service and timer, not bare cron. Order it after network availability and any application writer/sync service that must finish first. A timer example (`OnCalendar=daily`, `RandomizedDelaySec=30m`, `Persistent=true`) is illustrative only; replace the cadence/jitter with owner-approved values.
- Set `Persistent=true` when missed timers should run after host downtime; use an approved schedule and randomized delay.
- Restrict filesystem paths, temporary directories, CPU/I/O priority, and network permissions; keep the environment file root-only.
- Alert on unit failure and separately on snapshot freshness/RPO violations (for example, inspect `restic snapshots --latest 1 --json`). A successful unit with no new snapshot is still a backup failure.
- Record last successful backup, last repository check, sampled restore result, and measured recovery time.

Official references: [restic releases](https://github.com/restic/restic/releases), [restic documentation](https://restic.readthedocs.io/), [rsync manual](https://download.samba.org/pub/rsync/rsync.1.html), [systemd.timer](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html), [Cloud Storage Object Versioning](https://cloud.google.com/storage/docs/object-versioning), and [Cloud Storage soft delete](https://cloud.google.com/storage/docs/soft-delete). Restic release checked 2026-10-28.