---
name: sec-code-semgrep-scan
description: "Run Semgrep-compatible pattern and taint scanning with OpenGrep as the default, or CodeQL for deeper dataflow analysis, including custom rules, baselines, SARIF, and CI gates. Use when a task mentions OpenGrep, Semgrep rules, CodeQL, custom SAST rules, `--baseline-commit`, or cross-language static scanning."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/sast-scanning]
  license: MIT
---

# Code pattern scan

Use OpenGrep for fast pattern scans by default; select CodeQL when deeper dataflow or query coverage is required and supported.

## Triggers

- Run OpenGrep/Semgrep-compatible rules, write a custom rule, or compare results with a baseline.
- Configure CodeQL database analysis, SARIF output, or static scan gating.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/code-scan.toml" exists
  REFERENCE "~/.junie/custom/configs/security/code-scan.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/pattern-and-codeql.md" for defaults
CACHE only the chosen engine, rules, baseline, or CI details
```

## Workflow

1. Identify languages, changed range, supported rules, network/metrics policy, and existing suppressions.
2. Read config; use OpenGrep `v1.33.0` by default or CodeQL CLI `v2.27.3` for deeper analysis (versions checked `2026-10-28`).
3. For PR feedback, compare against a merge-base/baseline and gate only new findings; run a full scan on the default branch or schedule.
4. Validate custom rules with positive and negative fixtures before enabling them as a blocking gate.
5. Keep rule sources pinned/reproducible, disable telemetry where supported, and keep SARIF private.

## Safety

- Do not use unpinned remote rule auto-discovery in CI; use reviewed local rules or fixed rulesets.
- Do not weaken a baseline or suppress a whole rule to silence one finding.
- Treat SARIF as sensitive metadata and redact before sharing.

## Related skills

- Python-native analyzers: `sec-python-sast-scan`.
- Bash static checks: `sec-bash-shellcheck-scan`.
- Credential detection: `sec-git-secrets-scan`.
- Dependency and image scanning: `sec-python-dependency-scan`, `sec-container-image-scan`.

## References

- [OpenGrep and CodeQL workflow](references/pattern-and-codeql.md)
