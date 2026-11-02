---
name: sec-python-dependency-scan
description: "Scan locked Python dependencies for known vulnerabilities with pip-audit and OSV-Scanner, including `uv.lock`, CI gating, triage, and expiring suppressions. Use when a task mentions `uv.lock`, `pip-audit`, `osv-scanner`, dependency CVEs, or Python software composition analysis."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/dependency-scanning]
  license: MIT
---

# Python dependency scan

Scan the locked dependency graph rather than an ambient environment; keep first-party code findings in the SAST skills.

## Triggers

- Audit Python dependencies, review a CVE in a lockfile, or add a dependency scan gate.
- Work with `uv.lock`, `pip-audit`, OSV IDs, or temporary vulnerability ignores.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/dependencies.toml" exists
  REFERENCE "~/.junie/custom/configs/security/dependencies.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/dependency-scanning.md" for defaults
CACHE only the lockfile, scan, or CI-gate guidance needed
```

## Workflow

1. Read the optional config and confirm the lockfile matches the project manifest before scanning.
2. Export the locked production dependency set and scan it with configured tools; include optional groups only if deployed.
3. Triage reachability, fix availability, and severity; prefer a minimal upgrade followed by tests.
4. Keep suppressions narrow, owned, reasoned, and time-limited; fail when an exception expires.
5. Start CI gates advisory only when a known backlog requires it; define the condition and date for making them blocking.

## Safety

- Pin tool versions in the project's lockfile or immutable build image; never run downloaded installers from a shell pipe.
- Do not auto-apply major upgrades; have a reviewed change update the lockfile and run tests.
- Keep PR validators free of publish permission and long-lived credentials.

## Related skills

- SBOM and artifact evidence: `sec-artifact-sbom-sign`.
- Container image CVEs: `sec-container-image-scan`.
- First-party Python vulnerabilities: `sec-python-sast-scan`.
- Compromised package response: `sec-supplyChain-attack-respond`.

## References

- [Python dependency scanning](references/dependency-scanning.md)
