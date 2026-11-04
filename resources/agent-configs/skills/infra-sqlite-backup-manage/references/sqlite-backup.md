# SQLite backup and restore reference

## Decide whether the local database needs protection

Classify SQLite as a system of record or a derived cache. If it can be rebuilt from an authoritative upstream store, validate that rebuild path first; a local backup may only shorten RTO. Any SQLite system of record needs an off-host, encrypted copy under approved retention.

## Consistent backup

Never copy a live main database file and its `-wal`/`-shm` files independently. Use the SQLite online backup API or `VACUUM INTO`, which produces a consistent standalone copy. Choose an output path and fixed-format timestamp from trusted configuration; avoid paths containing untrusted quote characters because the SQLite CLI command embeds the path in SQL/meta-command text.

```bash
umask 077 &&
install -d -m "$BACKUP_DIRECTORY_MODE" -o "$DB_OWNER" -g "$DB_GROUP" "$OUTPUT_DIR" &&
runuser -u "$DB_OWNER" -- sqlite3 "$DB_PATH" \
  ".backup '$OUTPUT_DIR/config_${BACKUP_STAMP}.db'" &&
BACKUP_PATH="$OUTPUT_DIR/config_${BACKUP_STAMP}.db" &&
INTEGRITY=$(sqlite3 -readonly "$BACKUP_PATH" 'PRAGMA integrity_check;') &&
test "$INTEGRITY" = ok &&
sha256sum "$BACKUP_PATH" >"$BACKUP_PATH.sha256"
```

If using `VACUUM INTO`, ensure the destination does not already exist:

```bash
umask 077 &&
runuser -u "$DB_OWNER" -- sqlite3 "$DB_PATH" \
  "VACUUM INTO '$OUTPUT_DIR/config_${BACKUP_STAMP}.db'"
```

Restrict database/checksum permissions. Schedule capture after the application's write/sync unit where consistency requires it. Ship copies off-host with an approved versioned backup/object-storage policy; keep local rotation separate from offsite retention.

## Health checks

```bash
sqlite3 -readonly "$DB_PATH" 'PRAGMA integrity_check;' &&
sqlite3 -readonly "$DB_PATH" 'PRAGMA quick_check;' &&
sqlite3 -readonly "$DB_PATH" 'PRAGMA journal_mode;' &&
stat -c '%y %U:%G %a' "$DB_PATH"
```

`integrity_check` should return `ok`. Also compare schema version, freshness, representative row counts, and application-level invariants with the authoritative source where available. A clean structural check does not prove logical correctness or completeness.

## Restore or rebuild

1. Obtain approval and stop/quiesce the writer before touching the live path.
2. Preserve the current database and any `-wal`/`-shm` sidecars for rollback or investigation.
3. Prefer rebuilding a derived cache from its authoritative source using the deployed schema/configuration. Otherwise restore a verified copy to a new path first.
4. Set the expected owner, mode, and platform security context; on SELinux hosts, restore the configured file context.
5. Run `integrity_check`, compare key rows with the source, and verify application access before restarting the scheduled writer.
6. Restart the timer/unit and confirm the next scheduled sync and backup both succeed.

Official references: [SQLite Online Backup API](https://sqlite.org/backup.html) and [`VACUUM`](https://sqlite.org/lang_vacuum.html).