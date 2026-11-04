---
name: infra-network-loadBalancer-manage
description: "Design and operate Google Cloud load balancers for HTTP(S), TCP, UDP, and SIP ingress, including health checks, backend services, draining, and rollout safety. Use when a task mentions GCP load balancing, backend services, forwarding rules, health checks, or SIP passthrough."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/networking/load-balancing]
  license: MIT
---

# Google Cloud load balancing

## Triggers

- Select or configure a GCP load balancer for HTTP(S), internal traffic, or SIP/TCP/UDP ingress.
- Diagnose unhealthy backends, health-check reachability, forwarding rules, or draining.
- Plan a safe rollout or failover involving a GCP load-balanced service.

## Defaults

Use a global external Application Load Balancer for public HTTP(S), and a regional external passthrough Network Load Balancer for SIP/L4 ingress when its constraints fit. Never route SIP UDP or RTP through an HTTP(S) load balancer.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project network policy and AGENTS.md if present
IF file exists "~/.junie/custom/configs/infra/load-balancer.toml"
  REFERENCE that file for preferred GCP load-balancer defaults
ELSE
  use defaults listed here
REFERENCE "references/load-balancing.md"
IF SIP signaling or media behavior is involved
  REFERENCE skill "dev-kamailio-platform-manage"
CACHE only the relevant frontend, backend, health-check, or draining guidance
```

## Workflow

1. Map protocol, exposure, client-IP requirements, region/global scope, backend type, and availability needs; request unknown site CIDRs, ports, or IPs.
2. Inspect existing forwarding rules, backend services, health checks, firewall rules, and IaC ownership.
3. Choose the least complex GCP load-balancer class matching the protocol; do not use HTTP(S) products for SIP UDP or RTP.
4. Stage changes in IaC or a reviewed change plan; validate health-check reachability and backend readiness before cutover.
5. Drain backends, verify application behavior from external and internal paths, then record rollback steps.

## Safety

- Never invent client ranges, health-check ports, or production targets; ask for approved runtime values.
- Do not expose backend admin interfaces or allow health probes from broader sources than required.
- SIP signaling and RTP have different behavior: keep call-aware distribution in the SIP layer and do not treat RTP as HTTP traffic.

## Related skills

- GCP DNS records → `infra-gcp-cloudDns-manage`
- Reverse proxy configuration → `infra-nginx-reverseProxy-manage`
- SIP routing and dispatcher failover → `dev-kamailio-platform-manage`
- VPC firewall policy → `sec-gcp-firewall-manage`
- Infrastructure as code → `infra-opentofu-any-manage`, `infra-terraform-any-manage`

## References

- [references/load-balancing.md](references/load-balancing.md) — GCP product selection, SIP passthrough, health checks, and rollout.
