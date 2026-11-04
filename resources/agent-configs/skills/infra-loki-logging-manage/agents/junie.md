# Junie specifics — infra-loki-logging-manage

- Validate Loki and Alloy configs before reload/restart.
- Keep label cardinality bounded and redact sensitive log fields before shipping.
- No production change without approval; no commits.
