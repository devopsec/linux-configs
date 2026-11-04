---
name: infra-aws-rds-manage
description: "Provision and operate Amazon RDS and Aurora databases, including PostgreSQL, parameter groups, replicas, snapshots, point-in-time restore, Blue/Green deployments, and monitoring. Use when requests mention RDS, Aurora, AWS PostgreSQL, DB subnet groups, read replicas, PITR, or database failover."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-rds
  license: MIT
---

# AWS RDS manage

Use this skill for managed RDS/Aurora resource lifecycle and availability. Engine-level administration and organization-wide backup policy remain with their specialist skills.

## Triggers

- Provision, resize, patch, or troubleshoot RDS/Aurora databases.
- Configure encryption, IAM database authentication, replicas, or parameter groups.
- Restore a snapshot/PITR copy, plan a major upgrade, or test failover.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-rds.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-rds.toml"
ELSE use the defaults listed below
IF task involves RDS, Aurora, PostgreSQL, snapshots, replicas, or failover
  REFERENCE "references/rds.md"
CACHE only the loaded RDS guidance for this task
```

## Workflow

1. Identify engine, region, account, data classification, availability target, retention, and whether the database is IaC-managed.
2. Prefer Terraform/OpenTofu and private subnets. Require encryption, TLS, deletion protection, backups, and a tested restore path appropriate to the workload.
3. Review version support, extension compatibility, parameter changes, failover behavior, and cost before producing an apply plan.
4. Snapshot or verify recoverable backups before upgrades, restore, promotion, or deletion. Require explicit confirmation for destructive actions or promotion that breaks replication.
5. Verify database state, connectivity, alarms, replication lag, and restore results; preserve the original database until a restore is validated.

### Defaults when no config exists

- IaC changes: Terraform/OpenTofu; AWS CLI for read-only inventory and verification.
- PostgreSQL baseline checked 2026-10-28: RDS major 18 with latest published minor 18.6; run engine-version discovery in the target region before choosing a rollout target.
- Ask for engine, version, region, retention, RPO/RTO, and maintenance window when not supplied.

## Related skills

- PostgreSQL engine operations → `infra-postgresql-server-administer`
- Backup/DR policy → `infra-postgresql-backup-manage`, `infra-ops-drPlan-create`
- AWS networking and identity → `infra-aws-vpc-manage`, `infra-aws-iam-manage`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
