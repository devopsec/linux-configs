---
name: sec-python-sast-scan
description: "Select and run static security and quality analysis for Python with PyCharm inspections, Bandit, Ruff, Pylint, type/taint analyzers, and cross-links to OpenGrep, CodeQL, pip-audit, and Gitleaks. Use when a task mentions Python SAST, Bandit, Ruff security rules, PyCharm inspections, pylint, mypy, Pyre/Pysa, Pyright, Xenon, or `pyproject.toml` security checks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/sast-scanning]
  license: MIT
---

# Python SAST scan

Use a small, configured analyzer set that fits the repository; distinguish first-party source findings from dependency and secret scanning.

## Triggers

- Run or tune static analysis on Python source or add Python security checks to CI.
- Select PyCharm inspections, Bandit, Ruff, Pylint, mypy, Pyre/Pysa, Pyright, or Xenon.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/python.toml" exists
  REFERENCE "~/.junie/custom/configs/security/python.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/python-sast.md" for defaults
CACHE only selected analyzer settings and relevant finding guidance
```

## Workflow

1. Identify Python package roots, interpreter/uv setup, generated code, tests, and existing `pyproject.toml` settings.
2. Read the Python tool config; use the reference defaults if absent and pin selected executable versions in the project lock/build image.
3. Run focused changed-file checks, then a full-tree scan or baseline comparison; do not assume all tools support diff mode.
4. Triage findings, fix unsafe APIs, and keep suppressions narrow with a reason; never add broad global ignores without approval.
5. Route dependency CVEs to `sec-python-dependency-scan`, cross-language patterns/dataflow to `sec-code-semgrep-scan`, and credentials to `sec-git-secrets-scan`.
6. Report exact commands, findings by severity/rule, and resolved/deferred/suppressed status.

## Safety

- Keep scanner output in protected temporary storage; secret-bearing reports must be redacted before sharing.
- Avoid running untrusted build/test code merely to satisfy a scanner.
- Use parameterized queries, safe subprocess argument lists, and safe deserialization APIs as preferred fixes.

## Related skills

- OpenGrep/CodeQL: `sec-code-semgrep-scan`.
- Dependency auditing: `sec-python-dependency-scan`.
- Git secrets: `sec-git-secrets-scan`.
- Shell scripts: `sec-bash-shellcheck-scan`.

## References

- [Python analyzer roles, defaults, and diff-aware checks](references/python-sast.md)
