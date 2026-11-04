# Junie specifics — Pub/Sub

- Inspect topic, subscription, service-agent roles, and backlog before proposing mutation.
- Treat delivery as repeatable and require idempotency; do not promise exactly-once beyond supported constraints.
- Require approval for seek/replay, deletion, and retention changes.
