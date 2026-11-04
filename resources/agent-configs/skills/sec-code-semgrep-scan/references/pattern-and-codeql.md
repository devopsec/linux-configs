# OpenGrep patterns and CodeQL

## OpenGrep default

OpenGrep `v1.33.0` was the latest release page version checked on `2026-10-28`. Pin the binary/container to that release and verify provenance/checksums. Prefer reviewed local rules or a fixed ruleset; do not rely on unpinned remote auto-discovery in CI.

```bash
opengrep scan --metrics=off --config <reviewed-ruleset> --error <source-root>
opengrep scan --metrics=off --config <reviewed-ruleset> \
  --baseline-commit "$(git merge-base <base-ref> HEAD)" <source-root>
opengrep scan --metrics=off --config <local-rules-directory> <source-root>
```

Use a baseline/diff-aware run for PRs and a full scan on the default branch or schedule. Confirm the base ref is fetched and the merge-base is correct; fall back to a full scan if history is too shallow. Use local rule packs pinned to a reviewed commit when the scan must be reproducible.

## Custom patterns

Rules should state a stable ID, severity, actionable message, supported language, and narrow pattern. Add a positive fixture and at least one negative fixture before gating.

```yaml
rules:
  - id: python-subprocess-shell-true
    languages: [python]
    severity: ERROR
    message: "Use an argument list and avoid shell=True for untrusted commands"
    patterns:
      - pattern: subprocess.$F($CMD, ..., shell=True, ...)
```

Use inline suppressions with rule ID and reason; avoid whole-file/repository exclusions unless the path is generated or vendored and the rationale is documented.

## CodeQL deeper analysis

CodeQL CLI `v2.27.3` was the latest release page version checked on `2026-10-28`. Pin the CLI release, language pack, and query suite together. CodeQL is useful for deeper dataflow on supported languages; it does not replace Bash linting or secret detection.

```bash
codeql database create <database-dir> --language=python --source-root <source-root>
codeql database analyze <database-dir> \
  codeql/python-queries:codeql-suites/python-security-extended.qls \
  --format=sarif-latest --output=/tmp/codeql.sarif
```

Run full CodeQL analysis on a schedule or trusted default-branch build when PR build time is a constraint. Compare SARIF results against a reviewed baseline for PR feedback; do not suppress all old findings without a migration plan.

## CI and reporting

Keep PR scans non-publishing, use least-privilege CI identities, store SARIF privately, and define blocking policy by new severity/confidence. Disable metrics where supported. Record rule source, engine version, baseline commit, and unresolved finding ownership.