# Azure Key Vault

## Vault baseline

Use Azure RBAC authorization, purge protection, and a deliberate soft-delete retention period. For production, restrict public access and use a private endpoint with private DNS; validate the client's network path before changing permissions.

```bash
az keyvault create --name "${VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" --enable-rbac-authorization true \
  --enable-purge-protection true --retention-days 90
az keyvault secret set --vault-name "${VAULT_NAME}" --name "${SECRET_NAME}" \
  --file "${SECRET_FILE}"
az keyvault secret show --vault-name "${VAULT_NAME}" --name "${SECRET_NAME}" \
  --query id --output tsv
```

Keep the value in a protected file with restrictive permissions; query identifiers or attributes instead of secret contents. Use a managed identity for workloads and assign `Key Vault Secrets User` at the narrowest supported scope.

## Lifecycle and integrations

Set expiration and review versions as part of the rotation plan. Use key rotation policies for keys and certificate lifetime actions for certificates. For AKS, use the Secrets Store CSI driver with the Azure provider and avoid copying values into images or source configuration.

## Troubleshooting and destructive changes

For access denied, check RBAC mode, role scope, identity principal ID, and network restrictions. For name conflicts, inspect soft-deleted objects before creating another resource. Delete/purge, key disablement, and retention changes can be irreversible; explain recovery effects and request explicit approval first.