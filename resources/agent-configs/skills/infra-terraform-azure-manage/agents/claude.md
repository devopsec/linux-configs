# Claude Specifics for Infra Terraform Azure Manage

## Agent instructions

- Confirm tenant, subscription, identity, and environment before a plan.
- Prefer Entra ID/OIDC, Key Vault RBAC, private networking, and protected state.
- Require approval before production apply, purge, or database deletion.
