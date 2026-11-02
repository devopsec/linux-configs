# Azure managed databases — PostgreSQL Flexible Server and Azure SQL Database

Use PostgreSQL Flexible Server for PostgreSQL workloads and Azure SQL Database for SQL Server workloads. Engine DBA work → `infra-postgresql-server-administer`; backup policy/DR drills → `infra-postgresql-backup-manage` and `infra-ops-drPlan-create`.

## Contents
- Auth principle (Entra ID, no literal passwords)
- PostgreSQL Flexible Server: create, network, params, HA, replicas, backup/restore, upgrades
- Azure SQL Database: server, DBs, elastic pools, network, failover groups, backup, security
- Monitoring
- Terraform/OpenTofu
- Troubleshooting

## Auth principle

- Entra ID (Azure AD) admins + managed identities for apps. Disable password auth where possible (PG: `--password-auth Disabled`; SQL: `ad-only-auth enable`).
- If a bootstrap admin password is unavoidable: generate it, store it in Key Vault first, and pass via env var — never inline:
  `ADMIN_PW="$(az keyvault secret show --vault-name <kv> -n <db-admin-secret> --query value -o tsv)"` … `unset ADMIN_PW`.
- TLS 1.2+ only; clients verify server certs (`sslmode=verify-full` for PG).

## PostgreSQL Flexible Server

### Create (private access)

Versions checked 2026-10-28: PostgreSQL 18 is GA; versions 17, 16, 15, and 14 are also supported. PostgreSQL 11–13 left standard support on 2026-07-31. Query versions/SKUs available in the target region with `az postgres flexible-server list-skus -l <region>` before deployment.

```bash
az postgres flexible-server create -g <rg> -n <env>-<app>-pg --location <region> \
  --version 18 --tier GeneralPurpose --sku-name Standard_D4ds_v5 \
  --storage-size 128 --storage-auto-grow Enabled --performance-tier P15 \
  --high-availability ZoneRedundant --zone 1 --standby-zone 2 \
  --backup-retention 14 --geo-redundant-backup Enabled \
  --vnet spoke-<env>-vnet --subnet pg-delegated --private-dns-zone <env>.private.postgres.database.azure.com \
  --active-directory-auth Enabled --password-auth Disabled \
  --admin-object-id <entra-group-object-id> --admin-display-name "<db-admins-group>" --admin-type Group \
  --tags environment=<env> app=<app>
```

- Network options: VNet integration (delegated subnet `Microsoft.DBforPostgreSQL/flexibleServers`, private DNS zone `*.private.postgres.database.azure.com`) **or** public access + private endpoint (`privatelink.postgres.database.azure.com`, see `networking.md`). Choice is fixed at create time.
- App login with managed identity: create role via `pgaadauth_create_principal('<mi-name>', false, false)`; app fetches an Entra token (`az account get-access-token --resource-type oss-rdbms` for testing) as the password.

### Parameters

```bash
az postgres flexible-server parameter set -g <rg> -s <server> -n log_min_duration_statement --value 1000
az postgres flexible-server parameter set -g <rg> -s <server> -n idle_in_transaction_session_timeout --value 60000
az postgres flexible-server parameter set -g <rg> -s <server> -n azure.extensions --value pg_stat_statements,pgcrypto,postgis
az postgres flexible-server parameter set -g <rg> -s <server> -n require_secure_transport --value on
az postgres flexible-server restart -g <rg> -n <server>      # for static params (check isConfigPendingRestart)
```

Built-in PgBouncer: `pgbouncer.enabled=true` (port 6432). Extensions must be allow-listed in `azure.extensions` before `CREATE EXTENSION`.

### Replicas, backup/restore, upgrades

```bash
az postgres flexible-server replica create -g <rg> --replica-name <server>-read1 --source-server <server-id> --location <dr-region>
az postgres flexible-server replica promote -g <rg> -n <server>-read1 --promote-mode switchover --promote-option planned  # DR; verify flags
az postgres flexible-server restore -g <rg> -n <server>-pitr --source-server <server> --restore-time <yyyy-mm-ddThh:mm:ssZ>
az postgres flexible-server geo-restore -g <rg> -n <server>-geo --source-server <server-id> --location <paired-region>
az postgres flexible-server backup create -g <rg> -n <server> --backup-name pre-<change>   # on-demand
az postgres flexible-server upgrade -g <rg> -n <server> --version 18 --yes                 # DESTRUCTIVE: after backup, validation, and explicit owner confirmation
```

Restores create a new server — repoint config/DNS; keep the original until verified. Major upgrade: take on-demand backup, check extension compatibility, test on a PITR clone. Long-term retention: Azure Backup vault for PG Flexible (up to 10 years).

## Azure SQL Database

### Server and databases

```bash
az sql server create -g <rg> -n <env>-<app>-sql -l <region> \
  --enable-ad-only-auth --external-admin-principal-type Group \
  --external-admin-name "<db-admins-group>" --external-admin-sid <entra-group-object-id> \
  --enable-public-network false --minimal-tls-version 1.2 --assign-identity
az sql db create -g <rg> -s <server> -n <db> --edition GeneralPurpose --compute-model Serverless \
  --family Gen5 --capacity 4 --min-capacity 0.5 --auto-pause-delay 60 \
  --backup-storage-redundancy Zone --zone-redundant true
# prod OLTP: --edition BusinessCritical --service-objective BC_Gen5_4 --read-scale Enabled
# large: --edition Hyperscale --service-objective HS_Gen5_4 --ha-replicas 1
```

Elastic pools for many small DBs: `az sql elastic-pool create … --edition GeneralPurpose --capacity 4`, then `az sql db update … --elastic-pool <pool>`.

### Network

- Prefer private endpoint (`--group-id sqlServer`) + `--enable-public-network false`.
- If public access is temporarily needed, add a single /32 for the operator IP obtained from your own records (not via third-party IP-echo services), name it with an expiry, and delete it afterwards:
  `az sql server firewall-rule create -g <rg> -s <server> -n tmp-<user>-<yyyymmdd> --start-ip-address <ip> --end-ip-address <ip>`
- `0.0.0.0–0.0.0.0` ("Allow Azure services") opens the server to **all** Azure tenants — avoid.

### Failover groups (geo-DR)

```bash
az sql server create -g <rg> -n <server>-dr -l <dr-region> --enable-ad-only-auth \
  --external-admin-principal-type Group --external-admin-name "<db-admins-group>" --external-admin-sid <entra-group-object-id>
az sql failover-group create -g <rg> -s <server> -n <app>-fog --partner-server <server>-dr \
  --failover-policy Automatic --grace-period 1 --add-db <db>
az sql failover-group set-primary -g <rg> -s <server>-dr -n <app>-fog     # planned failover (test in DR drills)
```

Apps connect to `<app>-fog.database.windows.net` (listener), not the server name.

### Backup and restore

```bash
az sql db str-policy set -g <rg> -s <server> -n <db> --retention-days 14 --diffbackup-hours 12
az sql db ltr-policy set -g <rg> -s <server> -n <db> --weekly-retention P4W --monthly-retention P12M --yearly-retention P5Y --week-of-year 1
az sql db restore -g <rg> -s <server> -n <db> --dest-name <db>-restored --time <yyyy-mm-ddThh:mm:ssZ>
# BACPAC export: prefer SqlPackage (/Action:Export) with Entra auth; if using az sql db export, pass the storage SAS from Key Vault via env var, never an account key inline
```

### Security

```bash
az sql server audit-policy update -g <rg> -n <server> --state Enabled --lats Enabled --lawri <log-analytics-workspace-id>
az security pricing create -n SqlServers --tier Standard      # Defender for SQL (threat protection + vulnerability assessment)
az sql db tde show -g <rg> -s <server> --database <db>        # TDE on by default; CMK via Key Vault + server identity (get/wrapKey/unwrapKey)
```

Use Ledger, Always Encrypted, and dynamic data masking when required by the applicable data classification and compliance policy.

## Monitoring

Metrics: `cpu_percent`, `memory_percent`, `storage_percent`, `connections_failed` (PG), `active_connections`, replication lag (`physical_replication_delay_in_seconds`). Send diagnostic settings (PostgreSQLLogs, QueryStoreRuntimeStatistics / SQLInsights) to Log Analytics and the approved log sink.

```bash
az monitor diagnostic-settings create -n to-law --resource <db-resource-id> --workspace <law-id> \
  --logs '[{"categoryGroup":"allLogs","enabled":true}]' --metrics '[{"category":"AllMetrics","enabled":true}]'
```

## Terraform/OpenTofu

Azure CLI `2.91.0` and AzureRM provider `5.11.0` (checked 2026-10-28). Pin exact AVM/module versions reviewed for the workload; see `infra-terraform-avmModule-develop`. Raw PG:

```hcl
resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "${var.env}-app-pg"
  resource_group_name           = azurerm_resource_group.db.name
  location                      = azurerm_resource_group.db.location
  version                       = "18"
  sku_name                      = "GP_Standard_D4ds_v5"
  storage_mb                    = 131072
  auto_grow_enabled             = true
  backup_retention_days         = 14
  geo_redundant_backup_enabled  = true
  delegated_subnet_id           = azurerm_subnet.pg.id
  private_dns_zone_id           = azurerm_private_dns_zone.pg.id
  public_network_access_enabled = false
  zone                          = "1"
  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }
  lifecycle { prevent_destroy = true }
}
```

Azure SQL: `azurerm_mssql_server` with `azuread_administrator { azuread_authentication_only = true }` and no `administrator_login_password`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Can't connect (private) | DNS: private zone linked to client VNet; NSG on delegated subnet; port 5432/1433 |
| `no pg_hba.conf entry` / SSL error | `require_secure_transport`; client `sslmode=require/verify-full` |
| Entra login fails | token audience (`oss-rdbms` for PG, `database.windows.net` for SQL); principal created in DB |
| `CREATE EXTENSION` denied | add to `azure.extensions` |
| Major upgrade fails | region rollout / extensions / replicas must be removed first; run upgrade validation |
| DTU/vCore at 100 % | Query Store / `pg_stat_statements`; scale tier; pooling |
| PITR out of range | retention window; use LTR / Azure Backup vault |

