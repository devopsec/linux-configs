# Claude Specifics for Infra Network Loadbalancer Manage

## Context & Tuning
- Use the configured GCP product default and check existing resources/IaC before planning changes.
- Keep SIP signaling, RTP, HTTP(S), and health-check behavior distinct.

## Instructions Overrides
- Require approval for ingress exposure changes, production cutovers, or health-policy changes.
- Never invent runtime ports, CIDRs, targets, or IPs.
