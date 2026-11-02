# Junie CLI Specifics for Infra Sqlite Backup Manage

## Context & Tuning
- Determine whether SQLite is authoritative or rebuildable before recommending restore; load only the SQLite reference.
- Check for active writers and WAL mode before choosing a backup or recovery procedure.

## Instructions Overrides
- Never recommend copying a live database file as a consistent backup; preserve the known-good copy during recovery.

## Performance Notes
- Summarize verification and ownership checks without including database contents or secrets; do not commit changes.
