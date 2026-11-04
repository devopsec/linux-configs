# Junie specifics — Linux CIS scanning

- Read the Linux TOML if present, otherwise use the skill's pinned scanner defaults and confirm the profile for the OS.
- Run only read-only audits; keep generated remediation unexecuted and reports outside the repository.
- Treat skipped checks as unknown, protect host details, and make no commits.