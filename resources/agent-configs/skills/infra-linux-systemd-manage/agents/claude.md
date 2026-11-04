# Claude Specifics for Infra Linux Systemd Manage

## Context & Tuning
- Follow the systemd workflow and load only the active unit, timer, or journal guidance.
- Prefer repository-owned configuration and validate syntax before proposing a restart.

## Instructions Overrides
- Ask before production mutations, destructive override removal, or service restarts.
- Do not disclose credentials, private keys, or sensitive host identifiers.
