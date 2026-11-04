---
name: sec-sops-secrets-encrypt
description: "Encrypt and maintain secret-bearing files with SOPS using GCP KMS or age, including `.sops.yaml` rules, recipient changes, decryption at runtime, and rotation. Use when a task mentions SOPS, `.sops.yaml`, `sops edit`, age recipients, or encrypted YAML, JSON, or env files."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/secrets/sops-encryption]
  license: MIT
---

# SOPS secrets encrypt

Use SOPS when encrypted configuration must remain reviewable in version control; keep decryption identities outside the repository.

## Triggers

- Add or change SOPS creation rules or encrypted files.
- Rotate KMS or age recipients, re-encrypt data, or decrypt a file for a controlled runtime.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/sops.md"
CACHE only the encryption, recipient, or runtime sections needed
```

## Workflow

1. Identify the file format, key provider, authorized decryptors, and runtime destination.
2. Prefer GCP KMS identities for managed workloads; use age only when an offline or non-cloud recipient is required.
3. Encrypt with narrowly matched creation rules; verify the encrypted diff contains no plaintext values.
4. For access removal, remove the recipient, update keys, rotate the data key, then rotate the underlying credential.
5. Decrypt only into a protected temporary or runtime location, never stdout, chat, logs, or a committed file.

## Safety

- Keep age private keys and KMS decrypt permissions outside Git; public recipients are not secrets.
- Treat removal of a decryptor as insufficient if that principal may have copied plaintext; rotate the underlying secret.
- Use a package manager or checksum/signature-verified release; never pipe downloaded content into a shell.

## Related skills

- Runtime secret storage: `sec-gcp-secretManager-manage`, `sec-vault-secrets-manage`, `sec-aws-secretsManager-manage`, `sec-azure-keyVault-manage`.
- Scan for committed plaintext: `sec-git-secrets-scan`.

## References

- [SOPS and age workflow](references/sops.md)
