# Claude Specifics for Sec Tls Acme Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI load order and read only references relevant to the current ACME task.
- Inspect the repository and available tools before giving copy-ready commands; do not assume a DNS plugin or identity provider is installed.
- Keep endpoint and credential data in approved configuration; never expose a private key.

## Instructions Overrides
- Do not issue or renew a production certificate without explicit user approval.

## Performance Notes
- Use the renewal reference only for the challenge type and consumer involved.
