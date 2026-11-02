---
name: sec-artifact-sbom-sign
description: "Generate, sign, attest, and verify software artifact SBOMs and provenance with Syft, Cosign, CycloneDX, SPDX, and SLSA evidence. Use when a task mentions SBOM, `syft`, `cosign`, artifact attestation, signature verification, or provenance before release/deployment."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/sbom-supply-chain]
  license: MIT
---

# Artifact SBOM and signing

Bind inventory and provenance evidence to the exact immutable artifact that will be published or deployed.

## Triggers

- Create CycloneDX or SPDX output for a source tree, package, image, or model.
- Sign an artifact, attach an attestation, or verify evidence before deployment.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/sbom.toml" exists
  REFERENCE "~/.junie/custom/configs/security/sbom.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/sbom-signing.md" for defaults
CACHE only the SBOM format, signing identity, or verification workflow needed
```

## Workflow

1. Identify the immutable input digest and requested SBOM format; default to CycloneDX unless compliance requires SPDX.
2. Generate inventory from the locked source or exact built artifact and keep output adjacent to its release evidence.
3. Sign or attest with keyless workload identity or a KMS-backed key; bind identity and OIDC issuer during verification.
4. Verify signature, predicate, subject digest, and provenance before promotion; fail closed on mismatch.
5. Keep PR builds non-publishing and restrict release signing permission to the trusted release identity.

## Safety

- Pin tool images by digest and tool binaries by exact release/checksum; do not execute downloaded install scripts.
- Never sign a mutable tag when the deployed digest is known.
- Treat private signing keys and identity tokens as secret material; use managed key services or short-lived identity.

## Related skills

- Dependency advisories: `sec-python-dependency-scan`.
- Image scanning: `sec-container-image-scan`.
- Model integrity: `sec-mlModel-supplyChain-manage`.
- Secret handling: `sec-gcp-secretManager-manage` and `sec-vault-secrets-manage`.

## References

- [SBOM and signing workflow](references/sbom-signing.md)
