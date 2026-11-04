---
name: sec-git-secrets-scan
description: "Scan Git history, staged changes, and working trees for committed credentials with Gitleaks, using redacted local reports and narrow allowlists. Use when a task mentions Gitleaks, secret scanning, hardcoded credentials, leaked tokens, pre-commit detection, or Git history scanning."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [security/scanning/sast-scanning]
  license: MIT
---

# Git secrets scan

Use Gitleaks to detect likely secrets in changes and history; a finding is a possible exposure, not proof that a credential is safe to ignore.

## Triggers

- Scan a Git working tree, staged changes, commit range, or full repository history.
- Configure Gitleaks rules, redacted SARIF output, or a pre-commit/CI gate.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file "~/.junie/custom/configs/security/git-secrets.toml" exists
  REFERENCE "~/.junie/custom/configs/security/git-secrets.toml"
ELSE
  REFERENCE "assets/config.example.toml"
  REFERENCE "references/gitleaks.md" for defaults
CACHE only scan range, redaction, or allowlist guidance needed
```

## Workflow

1. Determine whether the request requires staged, diff-range, working-tree, or full-history coverage.
2. Read config and run Gitleaks `v8.30.1` (latest release page checked `2026-10-28`) with redaction enabled.
3. Store output privately; never display raw findings because reports may contain live credentials.
4. For each valid finding, rotate/revoke first, then remove from current files and coordinate any history rewrite with repository owners.
5. Add only narrow allowlist entries with a specific fixture/path rationale; re-run the scan after changes.

## Safety

- Do not paste secrets or unredacted reports into chat, PRs, or public artifacts.
- A clean current-tree scan does not prove Git history is clean; choose the range intentionally.
- Treat a detected real credential as compromised and hand off rotation to its owner.

## Related skills

- Provider-specific rotation: `sec-gcp-secretManager-manage`, `sec-sops-secrets-encrypt`, `sec-vault-secrets-manage`, `sec-aws-secretsManager-manage`, `sec-azure-keyVault-manage`.
- Python source findings: `sec-python-sast-scan`.
- Pattern scans: `sec-code-semgrep-scan`.

## References

- [Gitleaks workflow](references/gitleaks.md)
