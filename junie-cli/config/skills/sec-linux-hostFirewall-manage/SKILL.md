---
name: sec-linux-hostFirewall-manage
description: "Manage and audit Linux host firewalls using firewalld, nftables, ufw, or legacy iptables with lockout-safe change planning. Use when a request mentions host firewall rules, firewall-cmd, nftables, ufw, iptables, or firewall-audit.sh."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/firewall-config
  license: MIT
---

# Linux host firewall management

Choose one host firewall manager, review its active state, and plan least-privilege rules with an access rollback path. Do not mix firewalld-managed configuration with unmanaged nftables/iptables rules.

## Triggers

- Host firewall configuration, audit, rule review, or exposure finding
- firewalld, nftables, ufw, iptables, Docker host rules
- `firewall-audit.sh`

## Load order (SAD KITTI)

```sadkitti
REQUIRE host access path and confirmed rollback/console route before proposing changes
IF file exists "~/.junie/custom/configs/security/hostFirewall.toml"
  REFERENCE "~/.junie/custom/configs/security/hostFirewall.toml"
ELSE use defaults: detect the active manager; preserve existing policy; do not apply default-deny automatically
REFERENCE "references/host-firewalls.md"
IF task concerns cloud perimeter or SIP port matrix
  REFERENCE skill "sec-gcp-firewall-manage" or "sec-sip-exposure-manage"
CACHE only confirmed interface, manager, and approved sources
```

## Workflow

1. Run `bash scripts/firewall-audit.sh -q` for a read-only summary; protect full rule output because it may expose network topology.
2. Identify the active manager and determine required management, service, health-check, and return traffic before designing rules.
3. Use temporary/trial rules or syntax checking first; create a timed rollback before changes that could block remote access.
4. Apply only after explicit approval; validate allowed and denied paths, service behavior, and persistence.
5. Document exact source ranges and port values from user/config input, then update the maintained configuration source.

## Related skills

- GCP VPC firewall → `sec-gcp-firewall-manage`
- SIP/RTP perimeter requirements → `sec-sip-exposure-manage`
- Host baseline and SELinux → `sec-linux-host-harden`
- Active SIP tests → `sec-sip-securityTest-run`

## References

- [references/host-firewalls.md](references/host-firewalls.md) — host firewall selection and safe rule-management patterns.
- [scripts/firewall-audit.sh](scripts/firewall-audit.sh) — read-only local firewall and listener audit.
- [assets/config.example.toml](assets/config.example.toml) — manager selection and change-safety defaults.
