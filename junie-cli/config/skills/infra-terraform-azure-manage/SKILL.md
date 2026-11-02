---
name: infra-terraform-azure-manage
description: "Create, review, and troubleshoot Terraform HCL for Azure using `hashicorp/azurerm`, Entra ID/OIDC, virtual networks, NSGs, Key Vault RBAC, and PostgreSQL Flexible Server. Use when requests mention Terraform plus Azure, `azurerm_*` resources, ARM OIDC, or Azure-hosted infrastructure."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-azure/terraform-azure
  license: MIT
---

# Terraform Azure provider manage

Provider-specific HCL patterns for Azure. Use the generic Terraform core skill for module design, state, testing, and CI.

## Triggers

- Terraform with Azure, `hashicorp/azurerm`, `azurerm_*` resources
- Entra ID, OIDC/workload identity, Azure Storage backend, VNet/NSG, Key Vault, PostgreSQL Flexible Server

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or infrastructure README if present
IF task uses Azure provider resources or authentication
  REFERENCE "references/azure-provider.md"
  REFERENCE "assets/provider.azurerm.tf"
IF task needs generic Terraform state, module, test, or CI guidance
  REFERENCE skill "infra-terraform-any-manage"
IF task uses OpenTofu commands or encryption
  REFERENCE skill "infra-opentofu-any-manage"
IF the request concerns Azure operations rather than HCL
  REFERENCE the matching infra-azure-* service skill
CACHE tenant, subscription, location, identity, backend, and provider lockfile versions
```

## Workflow

1. Confirm tenant, subscription, location, environment, execution identity, and state backend.
2. Use Entra ID login locally and OIDC/workload federation in CI; do not store client secrets in HCL or tfvars.
3. Prefer RBAC for Key Vault, private networking, TLS, soft delete/purge protection, and managed database auth.
4. Keep subscription IDs, CIDRs, names, SKU sizes, and network ranges as reviewed inputs.
5. Run `terraform fmt -check`, `terraform validate`, and a saved plan; inspect replacements, RBAC scope, and soft-delete effects.
6. Require approval for production applies, purge, database deletion, or state operations.

## Related skills

- `infra-terraform-any-manage` — shared Terraform workflow, state, testing, and CI.
- `infra-terraform-gcp-manage` / `infra-terraform-aws-manage` — other provider HCL.
- `infra-opentofu-any-manage` / `infra-opentofu-migration-run` — OpenTofu runtime and migration.
- `sec-dev-threatModel-create` — threat-model identity and public-exposure changes.
