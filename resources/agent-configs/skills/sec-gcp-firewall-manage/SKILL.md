---
name: sec-gcp-firewall-manage
description: "Design, review, and manage GCP VPC firewall rules and network firewall policies with least-privilege sources, service-account targets, logging, and infrastructure-as-code. Use when a request mentions GCP firewall-rules, firewall policies, IAP access, or google_compute_firewall."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/firewall-config
  license: MIT
---

# GCP firewall management

Design cloud perimeter controls as reviewable infrastructure changes, using narrow sources and stable service-account targets where supported. Resolve project, VPC, ranges, and ports from approved runtime inputs.

## Triggers

- GCP VPC firewall rule or network firewall policy changes
- `gcloud compute firewall-rules`, IAP access, target tags/service accounts
- OpenTofu/Terraform `google_compute_firewall` changes

## Load order (SAD KITTI)

```sadkitti
REQUIRE approved project, VPC, target, protocol/port, and source ranges; ask if any are missing
IF file exists "~/.junie/custom/configs/security/gcp-firewall.toml"
  REFERENCE "~/.junie/custom/configs/security/gcp-firewall.toml"
ELSE use defaults: IaC-first, least-privilege sources, service-account targets, logging enabled
REFERENCE "references/gcp-firewall.md"
IF rules carry SIP/RTP traffic
  REFERENCE skill "sec-sip-exposure-manage"
CACHE confirmed runtime values; do not infer site CIDRs
```

## Workflow

1. Inventory intended flows and compare them with current VPC rules and policy evaluation order.
2. Reject public management/database/admin exposure; flag broad sources for explicit risk acceptance.
3. Prefer OpenTofu/Terraform and service-account targeting; review the plan before applying.
4. Use connectivity tests and firewall logs before deleting or replacing existing rules; do not probe arbitrary external targets.
5. Record owner, purpose, source, destination, ports, logging, expiry/review date, and rollback.

## Related skills

- Host firewall enforcement → `sec-linux-hostFirewall-manage`
- SIP/RTP port requirements → `sec-sip-exposure-manage`
- VPN connectivity → `sec-network-vpn-manage`
- IaC modules/policy → `infra-opentofu-any-manage`, `infra-terraform-any-manage`

## References

- [references/gcp-firewall.md](references/gcp-firewall.md) — GCP firewall model, IaC patterns, and read-only audit queries.
- [assets/config.example.toml](assets/config.example.toml) — IaC, logging, and broad-source approval defaults.
