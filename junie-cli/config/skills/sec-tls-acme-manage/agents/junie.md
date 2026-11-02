# Junie CLI Specifics for Sec Tls Acme Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order and read only the references needed for the current ACME task.
- Check the repository and configured tools before proposing commands; do not assume an optional DNS plugin or identity provider is present.
- Keep certificate names and credential sources in approved configuration; never infer a production endpoint or expose a private key.

## Instructions Overrides
- Do not issue or renew a production certificate without explicit user approval.

## Performance Notes
- Use the renewal reference only for the challenge type and consumer involved.
