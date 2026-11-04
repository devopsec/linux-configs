# Linux compliance scanning

## Tool versions

Versions checked 2026-10-28. Match SCAP content to the target OS release; the content package's revision must be recorded separately from the scanner version.

| Tool/content | Version | Source |
|---|---:|---|
| OpenSCAP | 1.4.6 | [official releases](https://github.com/OpenSCAP/openscap/releases) |
| ComplianceAsCode content | 0.1.82 | [official releases](https://github.com/ComplianceAsCode/content/releases) |
| Lynis | 3.1.7 | [official changelog](https://cisofy.com/changelog/lynis) |

Use distribution-signed packages when they provide the required exact version; otherwise use the approved signed release and checksum. Do not install from a piped shell script.

## Scan and remediation loop

1. Use a disposable or staging instance built from the intended image; obtain approval before any privileged audit.
2. Identify OS version, scanner/content versions, profile ID, scan time, and expected exclusions.
3. Run an audit/evaluation and save XML/HTML results outside the repository with restricted access.
4. Triage false positives and not-applicable controls; track exceptions by rule ID, reason, owner, and review date.
5. Remediate through maintained source/image configuration, then rescan and compare failed rule IDs.

## OpenSCAP

Discover installed content and profile identifiers instead of guessing:

```bash
oscap info <approved-datastream-path>
oscap xccdf eval --profile <confirmed-profile-id> \
  --results <private-results.xml> --report <private-report.html> <approved-datastream-path>
```

An evaluation exit code can indicate failed rules rather than a scanner error; inspect the report and exit status together. Content and profile availability differs by distribution. Tailor only with a documented requirement and keep the tailoring file versioned with the assessment.

Generated remediation is potentially destructive. Review every change, test it on a disposable instance, and never apply it automatically to production.

## Lynis and bundled audit

```bash
lynis audit system --quick --no-colors --report-file <private-report.dat> --logfile <private-log>
bash scripts/audit-host.sh
```

`audit-host.sh` is a quick read-only signal, not proof of CIS compliance. Its package-update checks use cached metadata only and do not refresh repositories. It emits `PASS`, `WARN`, `FAIL`, or `SKIP`; exit 1 means at least one failure, exit 2 means usage error. A non-root run intentionally skips checks requiring complete permissions. Store output privately because it may include host configuration and listener details.

Lynis is a general hardening signal; OpenSCAP with the correct profile/content is the compliance evidence. Do not compare scores across different OS/content/profile versions without noting the change.