# SBOM, signing, and provenance

## Formats and generation

Use CycloneDX for vulnerability matching and VEX workflows; use SPDX when licensing or a regulatory consumer requires it. Scan the locked source set and, separately, the exact built artifact because source inventories do not include every base-image package. Syft `v1.55.0` was the latest release page version checked on `2026-10-28`; pin the binary/image to this version and verify its release signature/checksum.

```bash
syft dir:. -o cyclonedx-json=sbom-source.cdx.json
syft "${IMAGE_BY_DIGEST}" -o cyclonedx-json=sbom-image.cdx.json
uv export --locked --all-packages --no-emit-workspace \
  --format cyclonedx1.5 > sbom-python.cdx.json
```

Keep SBOM output with the release evidence in a registry or protected artifact store with retention controls. Pin generator images to exact releases/digests in the toolchain configuration; use the platform package repository or checksum-verified release artifact, never an unpinned installer.

## Cosign

Cosign `v3.1.4` was the latest release page version checked on `2026-10-28`. Pin the binary/container to this release and verify release signatures/checksums before use. Prefer keyless OIDC signing in CI or a managed KMS key; avoid local private-key files.

```bash
cosign sign --key "gcpkms://<key-resource>" "${IMAGE_BY_DIGEST}"
cosign attest --key "gcpkms://<key-resource>" \
  --type cyclonedx --predicate sbom-image.cdx.json "${IMAGE_BY_DIGEST}"
cosign verify "${IMAGE_BY_DIGEST}" \
  --certificate-identity-regexp '^https://<trusted-issuer>/<org>/<repo>/' \
  --certificate-oidc-issuer "<trusted-oidc-issuer>"
```

For keyless verification, bind both the expected certificate identity and issuer. For KMS verification, specify the expected public key/KMS identity. Store the bundle with the artifact and verify the subject digest, predicate type, and signer before promotion.

## Provenance and deployment gate

Record source commit, build identity, toolchain, dependency lock, artifact digest, and SBOM digest. Cloud Build or another controlled builder can emit SLSA provenance; protect the release identity from untrusted PR jobs. Before deployment, verify the signature/attestation against an explicit policy and fail closed on missing or mismatched evidence.

## Troubleshooting

- Signature mismatch: sign and verify the same digest, not mutable tags.
- Missing packages: generate an SBOM from the built image as well as source.
- Keyless verification failure: confirm identity and OIDC issuer; do not weaken the trust expression to make it pass.
- SBOM not attached: preserve the exact output file and bundle in the release artifact store.