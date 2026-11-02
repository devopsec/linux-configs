# Terraform AzureRM provider

Use Terraform `1.17.0` and `hashicorp/azurerm` `5.11.0` as checked 2026-10-28. Pin the subscription and provider in code; keep `.terraform.lock.hcl` committed and isolate upgrades.

## Provider, identity, and backend

Use Entra ID locally and workload identity federation/OIDC in CI. Avoid client secrets and storage account keys. Set `subscription_id` explicitly (or through the supported ARM environment variable) and grant the deploy identity the minimum role at the resource-group/container scope.

```hcl
terraform {
  required_version = "= 1.17.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.11.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
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

For the `azurerm` backend, use Entra ID data-plane authentication and storage blob versioning/soft delete. Bootstrap state storage separately from the state it will hold.

```bash
az group create --name "$STATE_RESOURCE_GROUP" --location "$STATE_LOCATION"
az storage account create --name "$STATE_STORAGE_ACCOUNT" --resource-group "$STATE_RESOURCE_GROUP" \
  --sku "$STATE_STORAGE_SKU" --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false
az storage container create --name "$STATE_CONTAINER" \
  --account-name "$STATE_STORAGE_ACCOUNT" --auth-mode login
```

Use backend `use_azuread_auth = true` and grant the deploy identity `Storage Blob Data Contributor` on the container, not the whole subscription. Enable blob versioning and soft delete; keep bootstrap state separate.

## Network and NSGs

Use explicit VNet/subnet inputs and separate NSG rule resources; do not mix inline `security_rule` blocks and rule resources. Keep source prefixes, destination ports, locations, and public IP use explicit. Use Azure Bastion or just-in-time access rather than public SSH rules.

```hcl
resource "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_spaces
}

resource "azurerm_network_security_group" "service" {
  name                = var.nsg_name
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "service_ingress" {
  name                        = var.rule_name
  priority                    = var.rule_priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = var.protocol
  source_port_range           = "*"
  destination_port_range      = var.destination_port_range
  source_address_prefixes     = var.allowed_source_cidrs
  destination_address_prefix  = var.destination_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.service.name
}
```

## Key Vault and PostgreSQL

- Prefer Key Vault RBAC, private access, soft delete, and purge protection. Grant only required roles at the vault or secret scope.
- Do not include secret values in Terraform plans/state where write-only arguments or external secret injection can be used.
- Keep PostgreSQL Flexible Server private, encrypted, backed up, and protected from accidental deletion; use Entra ID auth where supported.
- Make zone, SKU, storage, retention, and HA choices explicit workload inputs.

```hcl
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                          = var.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = false
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = var.postgres_server_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgres_major_version
  sku_name                      = var.postgres_sku
  delegated_subnet_id           = var.postgres_subnet_id
  private_dns_zone_id           = var.postgres_private_dns_zone_id
  public_network_access_enabled = false
  backup_retention_days         = var.backup_retention_days
  zone                          = var.availability_zone

  lifecycle {
    prevent_destroy = true
  }
}
```

Add server authentication/HA blocks from the selected provider schema and platform policy. Avoid passwords in Terraform state; prefer Entra ID auth when supported and a separately managed secret channel otherwise.

## Review checklist

- Check `ARM_*` identity context and subscription before plan.
- Review role scope, NSG rules, public access, soft delete, and purge behavior.
- Run `terraform fmt -check`, `terraform validate`, and `terraform plan -out=tfplan`; test provider upgrades in a non-production stack first.
- Require explicit approval before apply or purge of soft-deleted resources.

## References

- [AzureRM provider registry](https://registry.terraform.io/providers/hashicorp/azurerm/5.11.0/docs) — published 2026-10-23; checked 2026-10-28.
- [AzureRM OIDC authentication](https://registry.terraform.io/providers/hashicorp/azurerm/5.11.0/docs#authenticating-to-azure) — checked 2026-10-28.