---
name: sec-azure-keyVault-manage
description: "Manage secrets, keys, identities, RBAC, network access, and rotation in Azure Key Vault using Azure CLI or SDKs. Use when a task mentions Key Vault, `az keyvault`, managed identities, Key Vault Secrets User, private endpoints, or secret versions."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/secrets/azure-keyvault]
  license: MIT
---

# Azure Key Vault manage

Use Key Vault for Azure workloads that need centrally controlled secrets, keys, and certificates.

## Triggers

- Create or update a vault/secret, assign access, configure a private endpoint, or review versions.
- Configure managed identities, RBAC, purge protection, certificate renewal, or AKS integration.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/azure-keyvault.md"
CACHE only the access, network, or lifecycle sections needed
```

## Workflow

1. Identify the vault, subscription/resource group, workload managed identity, and network boundary.
2. Prefer RBAC authorization and managed identities; grant the narrowest role at secret scope when supported.
3. Enable purge protection and appropriate retention before production secrets are added.
4. Set values from protected files and query identifiers/attributes rather than secret contents.
5. Verify private DNS, endpoint reachability, role assignments, expiration, and consumer behavior without printing values.

## Safety

- Do not put client secrets in application configuration when managed identity is available.
- Deletion, purge, key disablement, and retention changes can be irreversible or block recovery; explain impact and obtain confirmation.
- Treat unexpected public access or value disclosure as an incident and rotate affected credentials.

## Related skills

- Other backends: `sec-gcp-secretManager-manage`, `sec-sops-secrets-encrypt`, `sec-vault-secrets-manage`, `sec-aws-secretsManager-manage`.
- Secret scanning and leak handling: `sec-git-secrets-scan`.

## References

- [Azure Key Vault workflow](references/azure-keyvault.md)
