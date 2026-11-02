# SOPS and age

SOPS encrypts values in structured files while leaving non-secret metadata readable. The upstream SOPS release page reported `v3.13.3` as current when checked on `2026-10-28`; pin the binary/package or image to that exact version and verify its published checksums and signature before installation.

## Key choice and rules

Prefer GCP KMS identities for managed workloads. Use age for offline recipients or environments without a cloud KMS; keep age private keys in a protected secret store, not in Git or a workstation image.

```yaml
creation_rules:
  - path_regex: (^|/)secrets/production/.*\.(ya?ml|json|env)$
    gcp_kms: projects/<project-id>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>
  - path_regex: (^|/)secrets/development/.*\.(ya?ml|json|env)$
    age: age1<public-recipient>
```

Rules are evaluated in order; put narrower rules first. Use `encrypted_regex` only when the file intentionally contains non-secret fields that should remain visible.

## Daily use

```bash
sops edit secrets/<environment>/<file>.yaml
sops encrypt -i secrets/<environment>/<file>.yaml
sops updatekeys secrets/<environment>/<file>.yaml
sops rotate -i secrets/<environment>/<file>.yaml
```

Decrypt only to a protected runtime destination with restrictive permissions or use `sops exec-env` for a child process. Do not print decrypted output or commit decrypted files; exclude temporary plaintext from version control.

## Recipient removal

Remove the recipient from `.sops.yaml`, update the encrypted file's data key with `sops updatekeys`, then rotate the data key. If the removed recipient may have copied plaintext, rotate the underlying credentials as well. Check the final diff and run the secret scanner before merge.

## Installation policy

Use a supported package repository or a release binary whose checksum and signature/provenance were verified. Do not run downloaded installer scripts or pipe network data into a shell. Keep SOPS and Cosign versions pinned in the deployment toolchain.