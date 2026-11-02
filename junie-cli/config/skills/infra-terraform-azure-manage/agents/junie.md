# Junie CLI Specifics for Infra Terraform Azure Manage

## Agent instructions

- Confirm tenant, subscription, OIDC identity, backend, and environment before planning.
- Preserve Key Vault soft delete/purge protection and avoid credentials in state.
- Require review before production apply, purge, database deletion, or RBAC widening.
