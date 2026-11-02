# Claude Specifics for Infra Linux Blockstorage Manage

## Context & Tuning
- Follow the device-identity and backup gates before filesystem/LVM operations.
- Treat unknown disk IDs, filesystems, and mount paths as runtime inputs.

## Instructions Overrides
- Ask before destructive operations or resizing production data volumes.
- Do not suggest raw-device benchmarks or unverified repair commands.
