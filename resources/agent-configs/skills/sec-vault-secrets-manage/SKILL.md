---
name: sec-vault-secrets-manage
description: "Operate HashiCorp Vault or compatible OpenBao for dynamic credentials, PKI, policies, auth methods, audit, and Raft recovery. Use when a task mentions Vault, OpenBao, `vault kv`, AppRole, auto-unseal, database secrets engines, or Vault policies."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/secrets/hashicorp-vault]
  license: MIT
---

# Vault secrets manage

Use Vault only when managed cloud secret storage is not enough, such as dynamic credentials, internal PKI, or a multi-cloud broker.

## Triggers

- Configure Vault/OpenBao server storage, TLS, auth, secrets engines, or policies.
- Troubleshoot sealed state, token renewal, database credentials, PKI, or audit logs.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/vault.md"
CACHE only the server, auth, engine, or recovery sections required
```

## Workflow

1. Establish the product, version, deployment topology, storage backend, and recovery model before changing configuration.
2. Prefer Raft with TLS for a self-managed deployment; use an external KMS for auto-unseal only after validating IAM and key recovery.
3. Use workload identity or short-lived auth; keep policies scoped to required paths and capabilities.
4. Test changes in a non-production environment and verify audit events without printing tokens or secret values.
5. Treat initialization, recovery, seal, restore, and key rotation as operator-controlled operations; request confirmation before irreversible actions.

## Safety

- Never run a development server on a shared host or expose root/recovery material in output.
- Back up Raft snapshots with encryption and access separation; verify restore procedures before relying on them.
- Pin the Vault binary and container by an immutable version/digest; compatible forks may have independent release and licensing requirements.

## Related skills

- Simpler cloud runtime secrets: `sec-gcp-secretManager-manage`, `sec-aws-secretsManager-manage`, `sec-azure-keyVault-manage`.
- Encrypted files in Git: `sec-sops-secrets-encrypt`.
- Threat modeling secret paths: `sec-dev-threatModel-create`.

## References

- [Vault/OpenBao operational workflow](references/vault.md)
