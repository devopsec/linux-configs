---
name: infra-mongodb-server-administer
description: "Administer MongoDB deployments: mongod configuration, TLS and access control, users, replica sets, indexes, query diagnostics, monitoring, and safe upgrades. Use when tasks mention MongoDB, mongod, mongosh, replica sets, FCV, oplog, WiredTiger, or MongoDB indexes."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/databases/mongodb
  license: MIT
---

# MongoDB server administer

Administer self-managed MongoDB instances and replica sets with TLS, authorization, least-privilege database users, and controlled upgrades.

## Triggers

- MongoDB installation, `mongod.conf`, users, roles, TLS, or network binding
- Replica-set health, failover, oplog window, or replication lag
- Index/query analysis, WiredTiger tuning, monitoring, or upgrades

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or database README if present
IF task involves MongoDB server administration, configuration, operations, or upgrades
  REFERENCE "references/mongodb.md"
CACHE the loaded reference summary for this task
```

## Workflow

1. Identify the MongoDB major/patch version, topology, primary/secondary state, storage, and auth source.
2. Start with read-only status and query diagnostics; verify a recovery point before data-affecting operations.
3. Plan replica-set and compatibility changes against the deployed feature compatibility version; upgrade one major at a time.
4. Validate member health, replication lag, application behavior, and rollback/recovery options after an approved change.

## Safety

- Enable authorization and TLS; bind only to required private addresses and never expose unauthenticated MongoDB.
- Read secrets from a protected environment or secret store; never print connection URIs or credentials.
- Confirm before killing operations, stepping down a primary, dropping data, or restoring with `--drop`.

## Related skills

- PostgreSQL, MySQL, and Redis administration: sibling database skills
- Managed MongoDB service: use the cloud provider's matching database-service skill, if available
- Backup and restore drills: `infra-any-backupRecovery-manage`
- Metrics and alerting: `infra-prometheus-metrics-manage`

## References

- [MongoDB administration](references/mongodb.md)
