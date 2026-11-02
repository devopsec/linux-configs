---
name: sec-supplyChain-attack-respond
description: "Respond to compromised, malicious, or typosquatted dependencies, build tools, registries, and CI actions. Use when a task mentions a malicious package, package compromise, typosquatting, exposed build token, dependency incident, or compromised scanner release."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/supply-chain-attack-response]
  license: MIT
---

# Supply-chain attack respond

Contain exposure first, preserve evidence, determine affected artifacts and identities, then rebuild from reviewed inputs.

## Triggers

- An advisory or investigation identifies a malicious package, compromised tool, or suspicious release.
- A CI job executed an untrusted dependency or may have exposed credentials.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
REFERENCE "references/attack-response.md"
CACHE only the incident phase needed; retain timestamps and evidence custody
```

## Workflow

1. Establish incident authority, time window, affected package/tool, and systems; preserve logs and relevant lockfiles.
2. Contain by pausing affected builds/releases and pinning or blocking the known-bad artifact through reviewed controls.
3. Identify where the version was resolved, executed, built, published, or deployed; scope CI identities and reachable secrets.
4. Hunt for indicators from authoritative advisories, rebuild clean environments from reviewed locks, and replace affected artifacts.
5. Rotate all credentials reachable by affected runs as a coordinated operation; verify new values without exposing them.
6. Record decisions and follow-up owners; notify security/operations owners under their incident process.

## Safety

- Do not execute or install suspect artifacts during analysis; use an isolated environment when static inspection is insufficient.
- Preserve evidence before cleanup; do not alter production state without incident authority.
- Rotate secrets only with the owning team and a consumer rollout plan; do not disclose secret values in the report.

## Related skills

- Dependency triage: `sec-python-dependency-scan`.
- Image and scanner integrity: `sec-container-image-scan`.
- Secret rotation: `sec-gcp-secretManager-manage`, `sec-aws-secretsManager-manage`, `sec-azure-keyVault-manage`, `sec-vault-secrets-manage`.
- Artifact evidence: `sec-artifact-sbom-sign`.

## References

- [Compromised dependency/tool response](references/attack-response.md)
