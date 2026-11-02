# Claude Specifics for Infra Linux Filebackup Manage

## Context & Tuning
- Confirm source, destination, consistency requirements, retention, and runtime configuration before choosing a tool.
- Load only the file-backup reference needed for restic, rsync, or timer work.

## Instructions Overrides
- Preview destructive synchronization/pruning and require explicit approval before deletion.

## Performance Notes
- Protect repository secrets and keys; report the checked restic version when relevant and never commit credentials.
