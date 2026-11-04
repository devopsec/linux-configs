---
name: sec-gcp-secretManager-manage
description: "Manage GCP Secret Manager secrets, IAM, versions, rotation notifications, CMEK, and runtime access through gcloud, client libraries, Cloud Build, or systemd. Use when a task mentions Secret Manager, gcloud secrets, secretAccessor, secret rotation, CMEK, or retrieving secrets for a GCP workload."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/secrets/gcp-secret-manager]
  license: MIT
---

# GCP Secret Manager manage

Use Secret Manager for runtime values that should not be stored in source, images, or deployment state.

## Triggers

- Add, access, rotate, disable, or audit a GCP secret version.
- Configure `roles/secretmanager.secretAccessor`, CMEK, or rotation notifications.
- Inject a secret into a Cloud Build job, VM service, or Python workload.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/gcp-secret-manager.md"
CACHE only the sections needed for the requested secret lifecycle change
```

## Workflow

1. Identify the secret consumer and its workload identity; never request or display the value.
2. Create the secret container separately from adding a value; use stdin or a protected file with restrictive permissions.
3. Grant access at the individual-secret scope to the workload identity; avoid exported service-account keys.
4. Use explicit versions or aliases when rollout timing matters; add a new version, roll consumers, then disable the old version.
5. Verify IAM and access audit events without printing secret material; treat any exposed value as compromised.
6. Before any disable/destroy/delete action, confirm consumer migration and rollback requirements with the user.

## Safety

- Secret version resources can persist plaintext in IaC state; prefer out-of-band version creation or write-only provider features.
- CMEK key disablement can make every protected version unreadable; plan key recovery and access before enabling it.
- A rotation topic only notifies; the operator-owned handler must update the upstream credential and roll consumers.

## Related skills

- Other secret backends: `sec-sops-secrets-encrypt`, `sec-vault-secrets-manage`, `sec-aws-secretsManager-manage`, `sec-azure-keyVault-manage`.
- Secret scanning and response: `sec-git-secrets-scan`.
- IaC patterns: `infra-opentofu-any-manage` and `infra-terraform-any-manage`.

## References

- [GCP Secret Manager workflow](references/gcp-secret-manager.md)
