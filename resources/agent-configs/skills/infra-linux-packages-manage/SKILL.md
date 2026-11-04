---
name: infra-linux-packages-manage
description: "Install, update, remove, pin, and troubleshoot packages and repositories on Debian-family and RHEL-family Linux hosts. Use when a task mentions apt-get, dpkg, dnf, rpm, repository signing, package holds, or security updates."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/servers/linux-administration]
  license: MIT
---

# Linux package administration

## Triggers

- Install, upgrade, downgrade, pin, or remove a package using distro-native tools.
- Add or repair a signed APT or RPM repository.
- Diagnose package ownership, dependency conflicts, or security update status.

## Load order (SAD KITTI)

```sadkitti
REQUIRE host change policy and project AGENTS.md if present
REFERENCE "references/packages.md"
IF an external repository is proposed
  REQUIRE publisher signing-key fingerprint and repository signature validation method
CACHE only the matching distro and package-management branch
```

## Workflow

1. Identify distro release, enabled repositories, package owner, production role, and rollback window.
2. Inspect candidate versions and dependencies without applying changes (`apt-cache policy`, `dnf info`, `dnf repoquery`).
3. Prefer official distro repositories and security-supported packages; use signed vendor repositories only when required.
4. Preview removals or dependency changes, then apply a narrow package transaction.
5. Check configuration-file deltas, service restart requirements, and application health; document any pin and its owner.

## Safety

- Never use an unverified `curl | sh` or `wget | bash` installer or pipe a key directly into a trust store.
- Avoid broad upgrade/removal transactions on production without approval and a tested rollback plan.
- Pinning is not a substitute for security maintenance; record why a pin exists and when to review it.

## Related skills

- Package-managed systemd units → `infra-linux-systemd-manage`
- RHEL/Debian terminology → `docs-rhel-terminology-translate`
- Host security baselines → `sec-linux-host-harden`
- Infrastructure-as-code package configuration → `infra-opentofu-any-manage`, `infra-terraform-any-manage`

## References

- [references/packages.md](references/packages.md) — package command map, signed repositories, updates, and troubleshooting.
