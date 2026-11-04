# Claude Specifics for Infra Sqlite Backup Manage

## Context & Tuning
- Determine whether the database is authoritative or rebuildable and whether writers/WAL are active.
- Load the SQLite reference and use an isolated restore path for verification.

## Instructions Overrides
- Do not advise copying a live SQLite file as a consistent backup or replacing the only good copy.

## Performance Notes
- Keep verification concise and avoid including database contents, secrets, or commits.
