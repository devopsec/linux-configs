---
name: sec-aws-secretsManager-manage
description: "Manage secrets in AWS Secrets Manager, including customer-managed KMS encryption, IAM scope, rotation, and workload retrieval through AWS CLI or SDKs. Use when a task mentions `aws secretsmanager`, `GetSecretValue`, Secrets Manager rotation, ECS secret injection, or AWS secret policies."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/secrets/aws-secrets-manager]
  license: MIT
---

# AWS Secrets Manager manage

Use AWS Secrets Manager for AWS workloads that need centrally managed, versioned secret values.

## Triggers

- Create, update, retrieve, rotate, or audit an AWS Secrets Manager secret.
- Scope `secretsmanager:GetSecretValue`, KMS decrypt, cross-account access, or ECS injection.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/aws-secrets-manager.md"
CACHE only the access, rotation, or retrieval sections needed
```

## Workflow

1. Identify the consuming role or workload identity, secret ARN, KMS key, and rotation owner.
2. Create/update values from a mode-restricted file or supported stdin flow; do not place values in command arguments or logs.
3. Grant `GetSecretValue` on the specific ARN and KMS decrypt on the required key; prefer workload roles over long-lived credentials.
4. For rotation, use an AWS-supported template when available and verify the new credential before promoting it.
5. Confirm cache expiry and rollback behavior; schedule deletion only after the recovery window and consumer impact are understood.

## Safety

- Secret strings in IaC state and shell history are exposure paths; keep values outside state and argv.
- Never force-delete a secret without explicit approval and a confirmed backup/recovery decision.
- Treat any value disclosed in logs or Git as compromised and coordinate rotation across consumers.

## Related skills

- Other secret backends: `sec-gcp-secretManager-manage`, `sec-sops-secrets-encrypt`, `sec-vault-secrets-manage`, `sec-azure-keyVault-manage`.
- Secret scanning: `sec-git-secrets-scan`.

## References

- [AWS Secrets Manager workflow](references/aws-secrets-manager.md)
