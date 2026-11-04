---
name: sec-sip-securityTest-run
description: "Run bounded, authorized SIP service checks against a named test endpoint using low-rate protocol probes and a one-call functional check. Use when a request mentions SIP security testing, Kamailio exposure, SIPp, SIP OPTIONS, or RTP verification."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/scanning/vulnerability-scanning
    - security/operations/penetration-testing
  license: MIT
---

# SIP security testing

Assess only an explicitly authorized SIP/RTP endpoint with low-impact reachability and functional checks. This skill is not a credential-auditing, enumeration, fuzzing, stress, or flood-test workflow.

## Triggers

- SIP/Kamailio exposure, SIP OPTIONS check, TLS listener check, RTP call verification
- SIPp smoke test or SIP security test plan

## Load order (SAD KITTI)

```sadkitti
REQUIRE written authorization, named SIP target, source, test window, and stop contact
IF any boundary is missing or target is a carrier/partner endpoint -> ABORT and request clarification
IF file exists "~/.junie/custom/configs/security/sip-securityTest.toml"
  REFERENCE "~/.junie/custom/configs/security/sip-securityTest.toml"
ELSE use defaults: Nmap 7.992, SIPp 3.8.0, one test call, no enumeration or load tests
REFERENCE "references/sip-checks.md"
CACHE approved target and test limits only
```

## Workflow

1. Confirm that the target is a staging/test endpoint or explicitly approved, with a maintenance window and rollback/stop contact.
2. Verify expected listeners using a single low-rate probe from an approved source; do not scan arbitrary ranges.
3. If functional behavior must be checked, use a reviewed SIPp scenario for at most one test call; inspect custom scenario files before use.
4. Verify expected signalling and a controlled two-way media call without sending malformed traffic or generating load.
5. Record redacted evidence and route exposure findings to the perimeter/TLS/Kamailio owners.

## Related skills

- Engagement authorization/reporting → `sec-ops-pentest-run`
- General host vulnerability scans → `sec-host-vulnScan-run`
- SIP/RTP perimeter fixes → `sec-sip-exposure-manage`
- SIP configuration → `dev-kamailio-platform-manage`

## References

- [references/sip-checks.md](references/sip-checks.md) — safe SIP reachability and functional checks.
- [assets/config.example.toml](assets/config.example.toml) — one-call and low-rate safety defaults.
