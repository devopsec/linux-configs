---
name: sec-linux-host-harden
description: "Harden Linux hosts with distro-native SSH, kernel, account, MAC, audit, package-update, and systemd controls. Use when a request mentions Linux security baseline changes, sshd, sysctl, PAM, auditd, SELinux, AppArmor, or systemd sandboxing."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/hardening/linux-hardening
  license: MIT
---

# Linux host hardening

Apply a distro-aware baseline through reviewed, reversible configuration changes. This skill covers baseline controls; compliance scanning and benchmark reporting belong to `sec-linux-cis-scan`.

## Triggers

- Linux host hardening or baseline remediation
- `sshd_config`, `sysctl`, PAM, auditd, SELinux, AppArmor, security updates
- systemd service sandboxing or Linux file-permission review

## Load order (SAD KITTI)

```sadkitti
REQUIRE target OS and access path; ask for user approval before applying changes
IF task involves SSH, sysctl, PAM, accounts, auditd, permissions, or systemd
  REFERENCE "references/baseline.md"
IF task involves distro policy, SELinux/AppArmor, package updates, or crypto policy
  REFERENCE "references/distro-rhel-debian.md"
IF compliance benchmark results are needed
  REFERENCE skill "sec-linux-cis-scan"
CACHE only confirmed OS facts and approved exceptions
```

## Workflow

1. Identify OS/version, host role, access path, service dependencies, and rollback route before drafting changes.
2. Prefer vendor-supported drop-ins and idempotent configuration; do not edit generated/vendor files in place.
3. Separate access, kernel, MAC, audit, and service changes into reviewable steps; record justified exceptions.
4. Validate syntax and effective configuration before reload; keep an alternate console/session for remote access changes.
5. Test affected services and report changed controls, exceptions, validation, rollback, and residual risk.

## Related skills

- CIS/OpenSCAP/Lynis scans → `sec-linux-cis-scan`
- Host firewall controls → `sec-linux-hostFirewall-manage`
- VPN/routing host configuration → `sec-network-vpn-manage`
- SIP application config → `dev-kamailio-platform-manage`

## References

- [references/baseline.md](references/baseline.md) — SSH, kernel, accounts, permissions, audit, and systemd.
- [references/distro-rhel-debian.md](references/distro-rhel-debian.md) — RHEL-family and Debian-family differences.
