---
name: sec-linux-cis-scan
description: "Run read-only Linux baseline and CIS-style compliance scans with OpenSCAP, Lynis, or the bundled audit-host.sh, then triage results and track exceptions. Use when a request mentions CIS scanning, OpenSCAP, SCAP, Lynis, InSpec, or host baseline evidence."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/hardening/cis-benchmarks
  license: MIT
---

# Linux CIS and compliance scan

Collect read-only baseline evidence, identify applicable benchmark profiles, and plan remediation in source control. Do not apply generated remediation automatically.

## Triggers

- CIS benchmark scan, compliance evidence, baseline drift, exception tracking
- OpenSCAP / `oscap`, SCAP Security Guide, Lynis, InSpec
- Run or review `audit-host.sh`

## Load order (SAD KITTI)

```sadkitti
REQUIRE target OS/version and approval for any privileged local audit
IF file exists "~/.junie/custom/configs/security/linux.toml"
  REFERENCE "~/.junie/custom/configs/security/linux.toml"
ELSE use defaults: OpenSCAP 1.4.6 and Lynis 3.1.7; choose only a profile confirmed by oscap info
REFERENCE "references/cis-scanning.md"
IF task needs baseline control guidance
  REFERENCE skill "sec-linux-host-harden"
CACHE OS version, selected profile, and scan limits
```

## Workflow

1. Scan a disposable or staging host built from the intended image; capture OS, benchmark/content version, profile, and scan time.
2. Use `bash scripts/audit-host.sh` for a quick local read-only check; root is optional, and skipped checks must remain visible.
3. Prefer an audit/evaluation profile; save XML/HTML reports outside the repository in a private location.
4. Triage applicability and false positives; track each exception with rule ID, reason, owner, and review date.
5. Remediate in configuration/image source, then rescan and compare rule IDs. Never run generated `--remediate` output without explicit human review and a disposable-host trial.

## Related skills

- Baseline remediation → `sec-linux-host-harden`
- Firewall exceptions → `sec-linux-hostFirewall-manage`
- Findings from active network scans → `sec-host-vulnScan-run`

## References

- [references/cis-scanning.md](references/cis-scanning.md) — scan loop, tools, profile selection, and benchmark checklist.
- [scripts/audit-host.sh](scripts/audit-host.sh) — read-only local audit; exits 1 when it reports FAIL, 2 on usage error.
- [assets/config.example.toml](assets/config.example.toml) — pinned scanner/content versions and explicit profile confirmation.
