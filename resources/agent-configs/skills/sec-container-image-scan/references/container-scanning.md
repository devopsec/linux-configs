# Container image scanning

## Version and target

Trivy `v0.76.1` and Grype `v0.121.0` were the latest release page versions checked on `2026-10-28`. Pin the executable or image to those exact releases/digests and verify release checksums/signatures. Do not use the compromised Trivy `v0.69.4` artifact identified in the 2026 incident. Trivy is the default scanner; Grype is an optional alternative.

Resolve and scan the immutable image digest intended for deployment. Tags can move between scan and release.

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed "${IMAGE_BY_DIGEST}"
trivy image --exit-code 1 --severity CRITICAL "${IMAGE_BY_DIGEST}"
trivy fs --scanners vuln,secret,misconfig .
trivy config "${INFRA_DIRECTORY}"
trivy image --format sarif --output /tmp/trivy.sarif "${IMAGE_BY_DIGEST}"
```

Use a checked-in config to exclude generated fixtures only when the exclusion is justified. Keep exception entries narrow and include vulnerability ID, reason, owner, and expiry.

## CI and registry results

Run PR scans against the digest built for that change; fail on new findings at the agreed severity, and run scheduled full scans to catch new advisories. For a known backlog, keep existing findings advisory while documenting the date/condition for blocking. Artifact Registry continuous scanning and on-demand scans complement, but do not replace, scanning the exact digest that is deployed.

## Remediation

- Prefer a patched base image pinned by digest; rebuild even if application source is unchanged.
- Use minimal base images and multi-stage builds; omit package managers and compilers from final stages where possible.
- Distinguish fixed from unfixed vulnerabilities; do not suppress a finding solely because no patch is available.
- Keep scanner DB refresh controlled; use a cache only as a performance optimization, not as a substitute for freshness.

## Output handling

SARIF and JSON reports may reveal file paths, package inventories, or secret matches. Write them to a protected temporary/private artifact location, redact before sharing, and never attach raw results to public pull requests.