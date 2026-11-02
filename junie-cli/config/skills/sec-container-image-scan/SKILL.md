---
name: sec-container-image-scan
description: "Scan container images, filesystems, and build configuration for vulnerabilities and misconfiguration with Trivy or Grype, including Artifact Registry results and CI thresholds. Use when a task mentions Trivy, Grype, image CVEs, base-image digests, or container vulnerability scanning."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/container-scanning]
  license: MIT
---

# Container image scan

Scan the exact digest intended for deployment and separate fixable findings from unfixed advisories.

## Triggers

- Scan a container image, filesystem, Dockerfile, or infrastructure configuration.
- Configure Trivy/Grype, Artifact Registry scanning, SARIF output, or a CI threshold.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/container.toml" exists
  REFERENCE "~/.junie/custom/configs/security/container.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/container-scanning.md" for defaults
CACHE only the scanner, target digest, or CI threshold guidance needed
```

## Workflow

1. Resolve the image to an immutable digest and establish authorization to scan it.
2. Read the config; use Trivy as the default scanner unless the configured policy selects another tool.
3. Scan relevant image layers and configuration, capture redacted SARIF/table output, and triage severity and fix availability.
4. Gate on new high-confidence findings, not an unreviewed legacy backlog; assign owners and expiry to exceptions.
5. Rebuild and rescan the exact release digest after fixes; keep registry publishing rights out of untrusted PR jobs.

## Safety

- The scanner's database and binary are dependencies: pin exact versions/digests and verify release checksums/signatures.
- Avoid mutable tags and report outputs that could contain credentials.
- Do not suppress an unfixed issue without a reason, owner, and review date.

## Related skills

- Artifact SBOM/signature evidence: `sec-artifact-sbom-sign`.
- Dependency lockfiles: `sec-python-dependency-scan`.
- Compromised scanner/tool response: `sec-supplyChain-attack-respond`.

## References

- [Container scanning workflow](references/container-scanning.md)
