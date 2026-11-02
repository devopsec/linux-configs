---
name: sec-network-vpn-manage
description: "Plan and manage private administrative or site-to-site VPN connectivity using IAP, WireGuard, Tailscale, OpenVPN, or GCP HA VPN. Use when a request mentions VPN access, WireGuard, OpenVPN, Tailscale, Cloud VPN, tunnels, or routed private networks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/vpn-setup
  license: MIT
---

# Network VPN management

Choose the smallest VPN design that meets the approved administrative or site-to-site need. Resolve addresses, routed prefixes, peer IDs, and secret references from user-approved configuration.

## Triggers

- VPN connectivity or remote administration design
- WireGuard, OpenVPN, Tailscale, GCP HA VPN, BGP, tunnel troubleshooting

## Load order (SAD KITTI)

```sadkitti
REQUIRE approved use case, peer ownership, routes, addresses, and key-management plan
IF any CIDR, peer endpoint, or route is unknown -> ask the user; do not invent network values
IF file exists "~/.junie/custom/configs/security/vpn.toml"
  REFERENCE "~/.junie/custom/configs/security/vpn.toml"
ELSE use defaults: IAP for GCP administration, per-peer WireGuard keys for small private meshes, OpenVPN 2.7.8 for compatibility
REFERENCE "references/vpn-patterns.md"
CACHE only approved peers, routes, and design choice
```

## Workflow

1. Prefer IAP for GCP VM administration when it meets the need; select a managed or site-to-site VPN only for a defined requirement.
2. Design least-privilege routes and peer ACLs; explicitly identify forwarding/NAT and the cloud and host firewall changes required.
3. Keep private keys and PSKs in Secret Manager or another approved vault; never write secrets to chat, repository, or command history.
4. Review IaC and route changes before applying; establish a separate console/rollback path before changing remote access.
5. Verify tunnel state and permitted routes, then test denied routes and record key rotation/revocation steps.

## Related skills

- Linux forwarding and host firewall → `sec-linux-host-harden`, `sec-linux-hostFirewall-manage`
- GCP VPC rules → `sec-gcp-firewall-manage`
- Access threat model → `sec-dev-threatModel-create`

## References

- [references/vpn-patterns.md](references/vpn-patterns.md) — VPN selection, key handling, routing, and troubleshooting.
- [assets/config.example.toml](assets/config.example.toml) — VPN selection and route-review defaults.
