# Claude Specifics for Infra Servicemesh Any Manage

## Agent instructions

- Resolve mesh and exact version from config/cluster constraints; do not combine control planes casually.
- Keep identity keys out of source and redact live traffic/proxy output.
- Pilot injection/policy changes and require approval before cluster-wide enforcement.
