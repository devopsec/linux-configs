# Compromised dependency, tool, or CI action

## Contain and preserve

1. Confirm incident authority, affected package/tool/version, time window, and systems; preserve advisory details, lockfiles, CI logs, registry events, and image digests.
2. Pause affected release/build triggers as authorized. Prevent new resolutions by blocking the known-bad version at the registry/proxy or pinning a known-good version through a reviewed change.
3. Keep evidence immutable; do not run the suspect artifact or clean affected hosts before collection is approved.

## Scope execution and credentials

Inventory lockfiles, image SBOMs, package caches, build history, deployments, developer environments, and downstream artifacts during the exposure window. Determine whether the package was merely resolved or actually installed/imported/executed. Use authoritative indicators from the vendor/advisory to inspect isolated copies of the artifact and relevant endpoint/build logs.

For Python packages, review lockfile diffs, package metadata, unexpected startup hooks or `.pth` files, and suspicious process/network behavior. For other ecosystems, inspect lifecycle scripts and provenance before allowing another install. Do not broadly execute untrusted build steps to reproduce an incident.

## Eradicate and recover

1. Rebuild clean environments from a reviewed lockfile and trusted package source; rebuild images from clean base digests.
2. Remove malicious artifacts from caches and registries under incident authority; redeploy known-good artifacts.
3. Rotate every secret the affected build/run identity could access as a coordinated operation. Include cloud tokens, CI credentials, deployment keys, and package registry tokens; verify rotation without printing values.
4. Restore release triggers only after the owning security/operations authority approves and the trusted toolchain is pinned.

## Prevent recurrence

- Pin builder images, downloaded tools, CI actions, and model/package references by immutable digest or full commit.
- Keep PR identities non-publishing and least-privileged; use workload identity and short-lived tokens.
- Require lockfile review, provenance, signatures, and scheduled rescans; record owners and expiry for exceptions.
- Document timeline, impact, recovery evidence, and follow-up owners under the organization's incident process.

Do not include secret values or raw detection reports in the incident summary. Coordinate external notification through the designated incident owner.