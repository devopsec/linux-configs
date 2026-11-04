---
name: sec-sip-fraud-respond
description: "Triage and contain SIP toll fraud, credential abuse, REGISTER/INVITE floods, and suspicious SIP signaling. Use when a task mentions SIP fraud, abnormal call costs, premium-prefix abuse, SIP scanners, Kamailio pike/htable bans, CDR analysis, or SIP-edge containment."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/operations/incident-response
  license: MIT
---

# SIP fraud response

Respond to SIP abuse without losing evidence or applying unreviewed site-specific blocks. Coordinate service changes with the incident commander and carrier.

## Triggers

- Toll fraud, unexpected outbound calls, premium-prefix activity, CDR anomaly
- SIP REGISTER/INVITE flood, scanner User-Agent, pike/htable alarm, carrier abuse notice

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/security/incident-response.toml" exists
  REFERENCE "~/.junie/custom/configs/security/incident-response.toml"
ELSE
  ask the user for SIP target, htable, CDR source, RTP range, and applicable regulator before using site-specific steps
IF task involves fraud signals, containment, credential rotation, or SIP traffic evidence
  REFERENCE "references/sip-fraud-response.md"
IF task requires evidence preservation or incident roles
  REFERENCE skill "sec-ops-forensics-collect"
  REFERENCE skill "sec-ops-incident-respond"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Confirm the affected tenant/trunk, time window, business baseline, billing status, and approved change owner.
2. Preserve relevant signaling metadata and CDR evidence; avoid capturing media or collecting unnecessary caller data.
3. Classify severity; stop active billing with the narrowest reversible edge, account, or route control approved by the IC.
4. Compare source identities, called prefixes, authentication outcomes, and rate patterns against the configured CDR source and normal baseline.
5. Rotate abused credentials, correct the entry condition, validate normal calls, and remove temporary blocks only after approval.

## Safety

- Read htable names, CDR sources, RTP ranges, and target identifiers from the incident TOML or ask the user; never guess them.
- Treat signaling captures, phone numbers, and CDRs as sensitive personal data; restrict access and retention.
- Do not apply broad network blocks or modify dial plans without an approved rollback and carrier/IC coordination.

## Related skills

- General incident command and notification → `sec-ops-incident-respond`
- Evidence collection and custody → `sec-ops-forensics-collect`
- SIP TLS/mTLS controls → `sec-sip-tls-manage`
- Kamailio routing and module semantics → `dev-kamailio-platform-manage`
