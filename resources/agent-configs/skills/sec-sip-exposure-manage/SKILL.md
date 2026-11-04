---
name: sec-sip-exposure-manage
description: "Design the perimeter exposure policy for SIP signalling, SIP-TLS/WSS, RTP, and SIP administration interfaces. Use when a request mentions Kamailio exposure, SIP/RTP ports, SIP ALG, RTP ranges, SIP flood protection, or public SIP access."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/firewall-config
  license: MIT
---

# SIP/RTP perimeter exposure

Define which SIP, TLS, WebRTC, media, and administration flows must cross the network boundary. Use only user-confirmed source CIDRs and media port ranges; never infer site-specific values.

## Triggers

- SIP/RTP public exposure, Kamailio edge, WebRTC/WSS, RTP relay
- SIP ALG/conntrack helper, signalling rate limiting, media flow restrictions

## Load order (SAD KITTI)

```sadkitti
REQUIRE service role, approved peer/source ranges, configured RTP bounds, and desired signalling transports
IF any runtime range or target is unknown -> ask the user; do not use sample/site values
REFERENCE "references/sip-rtp-exposure.md"
IF implementation is host firewall or GCP VPC policy
  REFERENCE skill "sec-linux-hostFirewall-manage" or "sec-gcp-firewall-manage"
IF active verification is requested
  REFERENCE skill "sec-sip-securityTest-run"
CACHE only approved flow matrix
```

## Workflow

1. Build a flow matrix for signalling, TLS/WSS, media, health checks, management, RPC, and database traffic.
2. Confirm RTP min/max against the active media service configuration and obtain peer CIDRs from the user/config.
3. Keep RPC, database, control, and admin interfaces private; restrict signalling to known peers where possible.
4. Apply defence in depth: cloud policy, one host firewall manager, application-level rate limiting, and monitoring.
5. Validate using approved reachability and a controlled test call; never use floods or broad-range scans.

## Related skills

- GCP perimeter rules → `sec-gcp-firewall-manage`
- Linux host firewall → `sec-linux-hostFirewall-manage`
- SIP functional checks → `sec-sip-securityTest-run`
- Kamailio configuration → `dev-kamailio-platform-manage`
- SIP-TLS certificates → `sec-network-tls-manage`

## References

- [references/sip-rtp-exposure.md](references/sip-rtp-exposure.md) — SIP/RTP flow matrix, helper risks, and perimeter layers.
