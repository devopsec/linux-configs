# Junie specifics — infra-redis-server-administer

- Load only the matching Redis/Valkey reference and begin with read-only diagnostics.
- Require approval for flush, deletion, failover, or restore operations.
- Redact credentials and endpoints; no commits.
