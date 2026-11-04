# Junie specifics — Kubernetes cluster hardening

- Use only authorized clusters and report-only scan mode unless a user explicitly approves a change.
- Read the optional scanner config but never write under Junie home configuration.
- Confirm impact, version/profile, owner, and rollback before enforcement or remediation.
