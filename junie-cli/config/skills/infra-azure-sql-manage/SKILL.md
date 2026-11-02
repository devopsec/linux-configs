---
name: infra-azure-sql-manage
description: "Provision and operate Azure Database for PostgreSQL Flexible Server and Azure SQL Database, including private networking, Entra authentication, HA, replicas, failover groups, PITR, and monitoring. Use when requests mention Azure PostgreSQL, Flexible Server, Azure SQL, elastic pools, failover group, or database restore."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-azure/azure-sql
  license: MIT
---

# Azure SQL manage

Use this skill for Azure managed PostgreSQL Flexible Server and Azure SQL Database resource lifecycle. Database engine administration and backup policy belong with their specialist skills.

## Triggers

- Provision, scale, secure, or troubleshoot PostgreSQL Flexible Server or Azure SQL.
- Configure Entra authentication, private access, HA, replicas, or failover groups.
- Restore PITR/LTR data or plan an engine upgrade.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/azure-sql.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/azure-sql.toml"
ELSE use the defaults listed below
IF task involves Azure Database for PostgreSQL Flexible Server or Azure SQL Database
  REFERENCE "references/sql.md"
CACHE only the loaded Azure SQL guidance for this task
```

## Workflow

1. Identify engine, version, subscription, region, database owner, data classification, RPO/RTO, and IaC ownership.
2. Prefer Terraform/OpenTofu and private access. Use Entra ID/managed identity, TLS, encryption, backups, and deletion protection where supported.
3. Check engine/SKU/region availability, extension compatibility, maintenance, connection limits, and HA topology before proposing a plan.
4. Take or validate a backup before upgrades, failover, restore, or deletion; require explicit confirmation for irreversible or production-impacting actions.
5. Verify auth, DNS/network access, health metrics, backup retention, and restore/failover outcome; retain original resources until the recovery target is proven.

### Defaults when no config exists

- Azure CLI `2.91.0` and AzureRM provider `5.11.0` (checked 2026-10-28); lock the provider/module versions in IaC.
- Prefer PostgreSQL Flexible Server for PostgreSQL workloads; use Azure SQL for SQL Server workloads.
- Supported PostgreSQL baseline checked 2026-10-28: major 18 is available; query target-region SKUs and versions before choosing.
- Ask for engine, region, SKU, auth model, private-access choice, retention, and recovery objectives when absent.

## Related skills

- Azure networking and private DNS → `infra-azure-network-manage`
- PostgreSQL engine operations → `infra-postgresql-server-administer`
- Backup/DR policy → `infra-postgresql-backup-manage`, `infra-ops-drPlan-create`
- IaC and AVM workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`, `infra-terraform-avmModule-develop`
