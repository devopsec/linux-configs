# PostgreSQL backup and restore reference

## Choose a mechanism

| Mechanism | Useful for | Limits to plan for |
|---|---|---|
| `pg_dump` custom-format logical dump | Portability and database/object-level restore | Restore time grows with database size; include global roles separately |
| Physical base backup plus WAL archive | Point-in-time recovery for a self-managed cluster | Requires continuous archive monitoring, compatible tooling, and restore drills |
| Managed-service backup/PITR | Provider-managed scheduling and restore points | Confirm retention, deletion survival, region, permissions, and target behavior in the actual service |

## Cloud SQL for PostgreSQL

Cloud SQL automated backups and PITR are the managed baseline; add a logical export to a separate approved project/bucket when the recovery plan requires protection from instance/project deletion. Confirm edition, backup-vault mode, retention, regions, keys, and deletion behavior in the live instance before promising a recovery window.

```bash
gcloud sql instances describe "$INSTANCE" --project "$PROJECT" \
  --format='yaml(settings.backupConfiguration)'

gcloud sql instances patch "$INSTANCE" --project "$PROJECT" \
  --backup-start-time="$BACKUP_START_TIME" \
  --retained-backups-count="$RETAINED_BACKUPS" \
  --enable-point-in-time-recovery \
  --retained-transaction-log-days="$PITR_LOG_DAYS"

gcloud sql backups create --instance "$INSTANCE" --project "$PROJECT" \
  --description="pre-change $(date -u +%FT%TZ)" &&
gcloud sql backups list --instance "$INSTANCE" --project "$PROJECT" --limit 10
```

The `patch` command changes live instance settings; use an approved change and set retention values from policy. Confirm the instance service identity has create-only access to the export bucket, then create an offloaded logical export:

```bash
gcloud sql export sql "$INSTANCE" \
  "gs://${BACKUP_BUCKET}/cloudsql/${INSTANCE}/$(date -u +%Y%m%dT%H%M%SZ)-${DB_NAME}.sql" \
  --database="$DB_NAME" --offload --project "$PROJECT"
```

Before instance deletion, verify that retained backups/final backup survive deletion or that an independent export exists. Keep deletion protection enabled where required. Cloud SQL PITR creates a **new instance**; validate it before any cutover:

```bash
gcloud sql instances clone "$INSTANCE" "${INSTANCE}-restore-${RUN_ID}" \
  --point-in-time="$POINT_IN_TIME" --project "$PROJECT"
```

Restoring a backup to an existing instance overwrites the target. Use it only with an approved change, verified backup, and correct target identity:

```bash
gcloud sql backups restore "$BACKUP_ID" --restore-instance="$TARGET_INSTANCE" \
  --backup-instance="$INSTANCE" --project "$PROJECT"
```

An export can be imported into a scratch database on a new or approved target with `gcloud sql import sql`; never import over the production database as a test.

## Logical backup

Use a dedicated least-privilege role and a protected credential file or approved credential provider. Configure `PGPASSFILE` with restrictive permissions; never pass credentials through command-line arguments or dump logs. Grant only the server-version-appropriate read privileges.

```bash
umask 077 &&
pg_dump -h "$PGHOST" -U "$BACKUP_ROLE" -Fc -Z 6 -f "$OUT_FILE" "$DB_NAME" &&
pg_dumpall -h "$PGHOST" -U "$BACKUP_ROLE" --globals-only -f "$GLOBALS_FILE" &&
sha256sum "$OUT_FILE" "$GLOBALS_FILE" >"$CHECKSUM_FILE"
```

For a restore drill, create a new empty database and restore there:

```bash
createdb -h "$PGHOST" -U "$RESTORE_ROLE" "$RESTORE_DB" &&
pg_restore -h "$PGHOST" -U "$RESTORE_ROLE" -d "$RESTORE_DB" --no-owner --jobs=4 "$OUT_FILE"
```

Restore required roles and extensions deliberately, then compare schema, representative queries, row counts, and application behavior. Physical backups require a compatible server major version; for logical dumps, verify source/target compatibility and extensions. Use object selection (for example, a table) only after checking dependencies and ownership.

## Physical backup and PITR

For self-managed systems, coordinate a base backup with WAL archiving using a maintained backup tool such as pgBackRest or WAL-G. Monitor both backup completion and archive freshness; an incomplete WAL chain can invalidate the intended recovery point. Verify the recovery target and required keys are available before a drill. Pin the selected tool release and verify its published checksum/signature before installation; this skill does not prescribe a tool release.

```bash
pg_basebackup -h "$PGHOST" -U "$REPLICATION_ROLE" -D "$BASE_BACKUP_DIR" \
  --wal-method=stream --checkpoint=fast --format=tar --gzip
```

Managed database services differ in point-in-time windows, retention behavior after deletion, and restore target options. Inspect the deployed service configuration and current provider documentation; do not infer coverage from a default setting.

## Destructive actions and verification

- Treat `pg_restore --clean`, restoring onto an existing target, and deleting archived WAL/backups as destructive.
- Prefer a new restore target. Before any approved in-place operation, verify a separate fresh backup, destination identity, change window, and rollback path.
- Record source version, backup timestamp, restore point, extensions, checksum/integrity results, query checks, elapsed time, and exceptions.

Official references: [PostgreSQL backup and restore](https://www.postgresql.org/docs/current/backup.html), [`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html), and [`pg_restore`](https://www.postgresql.org/docs/current/app-pgrestore.html).

Cloud SQL references: [Cloud SQL for PostgreSQL backups](https://cloud.google.com/sql/docs/postgres/backup-recovery/backups), [PITR](https://cloud.google.com/sql/docs/postgres/backup-recovery/pitr), and [restore from backup](https://cloud.google.com/sql/docs/postgres/backup-recovery/restoring).