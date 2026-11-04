# Claude Specifics for Infra Postgresql Backup Manage

## Context & Tuning
- Confirm deployment type, database target, recovery point, owner-approved objectives, and current provider configuration.
- Load only the PostgreSQL reference needed for the task.

## Instructions Overrides
- Prefer isolated restores; do not make destructive changes without approval and a verified recovery point.

## Performance Notes
- Summarize checks, gaps, and measured recovery time; do not expose secrets or commit changes.
