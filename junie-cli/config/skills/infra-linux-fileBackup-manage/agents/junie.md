# Junie CLI Specifics for Infra Linux Filebackup Manage

## Context & Tuning
- Confirm source/destination, consistency needs, retention, and configuration before selecting restic or rsync.
- Load only the Linux file-backup reference; treat destination and timer values as runtime inputs.

## Instructions Overrides
- Require a reviewed dry run before rsync deletion or restic pruning; never expose repository passwords or keys.

## Performance Notes
- Keep restore evidence concise and avoid commits; state the pinned restic version's check date when relevant.
