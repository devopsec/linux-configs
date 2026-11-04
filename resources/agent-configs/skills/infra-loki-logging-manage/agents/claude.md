# Claude specifics — infra-loki-logging-manage

- Confirm schema, object-storage permissions, tenant model, and retention before deployment.
- Keep high-cardinality values in log content/structured metadata, not stream labels.
- Do not expose anonymous administrative access.
