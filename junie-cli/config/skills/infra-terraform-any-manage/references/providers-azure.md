# Provider: Azure (`hashicorp/azurerm`)

Azure-specific HCL only. Backend syntax/locking: [State Management](state-management.md#choosing-a-remote-backend); secrets/compliance: [Security & Compliance](security-compliance.md). Primary cloud is GCP ([providers-gcp.md](providers-gcp.md)). Snippets valid for `terraform` and `tofu`.

Contents: [Provider & auth](#provider-and-auth) · [State bootstrap](#state-storage-bootstrap) · [Network](#network-and-nsg-siprtp) · [Key Vault](#key-vault-rbac) · [PostgreSQL](#postgresql-flexible-server) · [Workflow fixes](#workflow-fixes-vs-upstream) · [Troubleshooting](#troubleshooting)

## Provider and auth

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0" # 5.11.0 latest as of 2026-10; 5.0 had breaking renames — read the 5.0 upgrade guide
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id # required since 4.0 (or ARM_SUBSCRIPTION_ID)

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
```

- Auth: `az login` locally; CI uses OIDC/workload identity federation (`ARM_USE_OIDC=true`, `ARM_CLIENT_ID`, `ARM_TENANT_ID`). No client secrets in tfvars.
- Install the CLI via the Microsoft package repo (`dnf`/`apt` with signed repo key), not `curl ... | sudo bash`.

## State storage bootstrap

```bash
az group create --name tfstate-rg --location westeurope
az storage account create --name "<unique-name>" --resource-group tfstate-rg \
  --sku Standard_ZRS --min-tls-version TLS1_2 --allow-blob-public-access false \
  --allow-shared-key-access false
az storage container create --name tfstate --account-name "<unique-name>" --auth-mode login
```

Backend: `use_azuread_auth = true` (Entra ID instead of storage keys); grant the deploy identity `Storage Blob Data Contributor` on the container. Enable blob versioning + soft delete for state recovery.

## Network and NSG (SIP/RTP)

```hcl
resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.30.0.0/16"]
}

resource "azurerm_subnet" "sip" {
  name                 = "sip-edge"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.30.1.0/24"]
}

resource "azurerm_network_security_group" "sip" {
  name                = "${var.name_prefix}-sip-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_rule" "sip" {
  name                        = "allow-sip"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*" # UDP+TCP 5060-5061
  source_port_range           = "*"
  destination_port_ranges     = ["5060", "5061"]
  source_address_prefixes     = var.sip_peer_ranges
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.sip.name
}

resource "azurerm_network_security_rule" "rtp" {
  name                        = "allow-rtp"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = var.rtp_port_range # e.g. "30000-40000"
  source_address_prefixes     = var.media_peer_ranges
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.sip.name
}

resource "azurerm_subnet_network_security_group_association" "sip" {
  subnet_id                 = azurerm_subnet.sip.id
  network_security_group_id = azurerm_network_security_group.sip.id
}
```

- Separate `azurerm_network_security_rule` resources (not inline `security_rule`) — avoids whole-NSG diffs; never mix both styles on one NSG.
- No SSH rule from `*` (upstream asset dropped for this) — use Azure Bastion or JIT access.
- SIP edges: Standard static public IP on the NIC; no NAT Gateway in front of SIP.

## Key Vault (RBAC)

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                          = "${var.name_prefix}-kv"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true # RBAC, not access policies
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

Write secrets with `value_wo` + `value_wo_version` on `azurerm_key_vault_secret` (write-only, 1.11+) or outside IaC — never via `-var="pw=$(...)"` on the CLI (shell history, process list, CI logs).

## PostgreSQL Flexible Server

```hcl
resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = "${var.name_prefix}-pg"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = "17" # verify latest supported
  sku_name                      = "GP_Standard_D4ds_v5"
  storage_mb                    = 131072
  backup_retention_days         = 14
  delegated_subnet_id           = var.pg_subnet_id
  private_dns_zone_id           = var.pg_private_dns_zone_id
  public_network_access_enabled = false
  zone                          = "1"

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  high_availability {
    mode = "ZoneRedundant"
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

Entra ID auth only ⇒ no admin password in config or state.

## Workflow fixes vs upstream

| Upstream did | Do instead |
|--------------|-----------|
| `terraform apply -auto-approve` with var-file | `plan -out` → review → `apply tfplan` |
| `terraform refresh` | `plan -refresh-only` (reviewable) |
| `terraform import` CLI | `import` blocks (1.5+) |
| Key Vault access policies | `rbac_authorization_enabled = true` + role assignments |
| azurerm `~> 3.80` | `~> 5.0`; `enable_*` → `*_enabled` renames (4.0) and 5.0 removals — run `plan` on a non-prod workspace first |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `subscription ID could not be determined` | 4.0+ requires it | `subscription_id` or `ARM_SUBSCRIPTION_ID` |
| `AuthorizationFailed` | Missing RBAC on scope | Assign least role on RG, not subscription Owner |
| Key Vault name already in use | Soft-deleted vault | Recover (feature flag) or pick new name; purge only deliberately |
| `ResourceGroupBeingDeleted` / destroy blocked | `prevent_deletion_if_contains_resources` | Remove stray resources first (intended guard) |
| NSG rules flip-flop | Inline `security_rule` + rule resources | Pick one style |
