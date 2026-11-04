---
name: sec-bash-shellcheck-scan
description: "Run ShellCheck against Bash and POSIX shell scripts, tune severity, review security-relevant diagnostics, and use warning backlogs safely. Use when a task mentions ShellCheck, `.shellcheckrc`, SC2086, shell linting, or adding a shell scan to CI."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/sast-scanning]
  license: MIT
---

# Bash ShellCheck scan

Use ShellCheck as a focused static check for shell scripts; review dangerous constructs manually even when the scanner is clean.

## Triggers

- Scan or configure shell scripts with ShellCheck.
- Triage SC2086/SC2046/SC2155 or establish a severity threshold in CI.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/shellcheck.toml" exists
  REFERENCE "~/.junie/custom/configs/security/shellcheck.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/shellcheck.md" for defaults
CACHE only file discovery, severity, or finding guidance needed
```

## Workflow

1. Discover tracked scripts by extension and shebang, then scope changed-file checks and full-tree checks separately.
2. Run ShellCheck at the configured threshold and capture JSON/SARIF only in a protected temporary location.
3. Fix quoting, argument construction, status handling, and unsafe temp-file patterns; review autofixes before applying.
4. Use narrow inline suppressions with a reason; ratchet an existing warning backlog without lowering the current gate.
5. Report commands, severity counts, fixes, and deferred findings.

## Safety

- Pin ShellCheck `v0.11.0` or a verified immutable image; this stable release was checked on `2026-10-28`.
- Do not run generated commands or auto-fixes without reviewing the diff.
- A clean scan does not make `eval`, untrusted `sudo` arguments, or downloaded shell installers safe.

## Related skills

- Python static analysis: `sec-python-sast-scan`.
- OpenGrep and CodeQL: `sec-code-semgrep-scan`.
- Git secret detection: `sec-git-secrets-scan`.
- Bash correctness/review: `dev-bash-script-review`.

## References

- [ShellCheck workflow](references/shellcheck.md)
