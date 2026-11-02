# Junie specifics — Linux host firewall

- Read the host-firewall TOML if present and run the bundled script only as a read-only audit.
- Confirm the active manager, existing remote-access path, and timed rollback before proposing changes.
- Do not apply rules remotely without explicit approval; redact topology and make no commits.