---
name: infra-redis-server-administer
description: "Administer Redis or Valkey: bind/authentication, ACLs, persistence, memory policy, Sentinel, cluster operations, monitoring, and client-safe patterns. Use when tasks mention Redis, Valkey, redis-cli, ACL, Sentinel, Redis Cluster, AOF, RDB, or Redis memory pressure."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/redis
  license: MIT
---

# Redis server administer

Operate Redis-compatible servers with a clear data role (cache, durable store, queue, or lock service), controlled network access, and explicit persistence choices.

## Triggers

- Redis/Valkey configuration, ACLs, TLS, memory, or persistence
- Sentinel failover, Cluster topology, replication, or client routing
- Redis latency, eviction, rejected connections, or data recovery

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or database README if present
IF task involves Redis/Valkey configuration, persistence, topology, or diagnostics
  REFERENCE "references/redis.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Identify the product and version, topology, data durability requirements, and whether eviction is acceptable.
2. Read-only inspect `INFO`, latency, memory, replication, and persistence state before changing settings.
3. Plan ACL, failover, or memory changes; confirm a restorable backup where data is durable and check client behavior.
4. Apply approved changes and verify role, replication, persistence, and application health.

## Safety

- Use ACLs and private binding; credentials come from Secret Manager or protected environment files, not command arguments.
- Choose eviction and persistence based on data semantics; do not treat a cache eviction policy as safe for queues or source-of-truth data.
- Explicitly approve `FLUSH*`, key deletion, failover, and restore operations. Avoid `KEYS *` and production `MONITOR`.
- Reference pins checked 2026-10-28: Redis `8.10.3`, Valkey `9.1.3`.

## Related skills

- PostgreSQL, MySQL, and MongoDB administration: sibling database skills
- Managed Redis services: `infra-gcp-any-manage`
- Backup and recovery: `infra-any-backupRecovery-manage`
- Metrics and alerts: `infra-prometheus-metrics-manage`

## References

- [Redis and Valkey administration](references/redis.md)
