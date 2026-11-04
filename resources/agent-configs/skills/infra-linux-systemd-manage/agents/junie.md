# Junie CLI Specifics for Infra Linux Systemd Manage

## Context & Tuning
- Execute SAD KITTI branches and load only the unit/timer/log reference needed for the task.
- Preserve repository-owned unit/install conventions and request unknown runtime values.

## Instructions Overrides
- No commits; do not restart production services or apply hardening without explicit approval.
- Redact credentials, private keys, and sensitive host details from summaries.
