# Junie CLI Specifics for Infra Postgresql Backup Manage

## Context & Tuning
- Load only the PostgreSQL procedure needed for the active deployment; check the repository's agent guidance when the task is project-specific.
- Confirm the database target, recovery point, and owner-approved RPO/RTO before suggesting commands.

## Instructions Overrides
- Prefer an isolated restore target; destructive changes require explicit approval and a fresh verified backup.

## Performance Notes
- Keep evidence summaries concise; never expose credentials or commit changes.
