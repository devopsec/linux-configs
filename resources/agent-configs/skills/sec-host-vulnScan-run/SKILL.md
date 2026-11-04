---
name: sec-host-vulnScan-run
description: "Run bounded vulnerability scans against explicitly authorized hosts or services using Nmap, Nuclei, or Greenbone. Use when a request mentions vulnerability scanning, host exposure, Nmap, Nuclei, OpenVAS, Greenbone, or scanner findings."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/scanning/vulnerability-scanning
  license: MIT
---

# Host vulnerability scan

Plan and run low-impact vulnerability checks only against an explicitly authorized scope. Do not attempt exploitation, credential guessing, persistence, lateral movement, or denial-of-service testing.

## Triggers

- Host or service vulnerability scan, exposure review, scanner result validation
- Nmap, Nuclei, OpenVAS / Greenbone, Nessus, CVSS triage

## Load order (SAD KITTI)

```sadkitti
REQUIRE written authorization naming exact targets, source, window, and stop contact
IF authorization, target, or window is absent -> ABORT and request it
IF file exists "~/.junie/custom/configs/security/host-vulnScan.toml"
  REFERENCE "~/.junie/custom/configs/security/host-vulnScan.toml"
ELSE use defaults: Nmap 7.992, Nuclei 3.11.1, rate cap 5 requests/second, no exploit-capable templates
REFERENCE "references/vulnerability-scanning.md"
CACHE only scope and tool constraints for this task
```

## Workflow

1. Confirm the target is owned/operated, approved, in-window, and not excluded; stop if any detail is unclear.
2. Start with inventory and passive checks. Select the least intrusive authorized scan and cap request rate/concurrency.
3. Use only reviewed safe checks/templates; do not run Nuclei code/JavaScript templates, exploit checks, or unreviewed template updates.
4. Validate findings without exploitation, record scanner/version, scope, timing, rate, evidence, confidence, and remediation.
5. Store reports privately with restricted access; escalate critical exposure to the named contact.

## Related skills

- Engagement authorization and reporting → `sec-ops-pentest-run`
- SIP-specific checks → `sec-sip-securityTest-run`
- Linux compliance baseline → `sec-linux-cis-scan`
- Code/IaC and dependency findings → `sec-code-sast-scan`, `sec-supplyChain-any-manage`

## References

- [references/vulnerability-scanning.md](references/vulnerability-scanning.md) — bounded network/host scanning, version pins, and triage.
- [assets/config.example.toml](assets/config.example.toml) — scanner versions and conservative rate defaults.
