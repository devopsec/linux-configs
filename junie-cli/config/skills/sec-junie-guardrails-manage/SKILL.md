---
name: sec-junie-guardrails-manage
description: "Review and safely manage Junie CLI allowlists, sandbox posture, and unattended CI execution. Use when users mention Junie settings, allowlist.json, sandbox.json, secure_credentials.json, headless runs, or agent-generated code controls."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/ai-coding-agent-guardrails
  license: MIT
---

# Junie Guardrails Management

Review Junie CLI enforcement separately from advisory project guidance. Report configuration posture without exposing credential values or making unapproved changes.

## Triggers

- Junie CLI `allowlist.json`, `sandbox.json`, global action approvals, or headless/CI controls.
- Agent-produced code review gates, sandbox isolation, or CI secret-scanning controls.

## Load order (SAD KITTI)

```sadkitti
IF task involves Junie settings, allowlists, or sandbox controls
  REFERENCE "references/junie-cli.md"
IF task involves repository/CI guardrails or unattended agents
  REFERENCE "references/repo-and-ci-controls.md"
CACHE only the security-relevant structure and decisions
```

## Workflow

1. Ask whether the scope is an interactive workstation, disposable VM/container, or unattended CI runner.
2. Inspect configuration shape, keys/types/counts, and rule ordering only; never open or print credential stores.
3. Recommend least privilege, narrow ask/allow patterns, sandboxing, egress limits, human review gates, and redacted audit logs.
4. Present proposed edits as a diff; change global Junie settings only with fresh, explicit approval.

Recommend `braveMode: Off` by default; recommend `Auto` only with an enforced sandbox and `On` only in a disposable sandbox. This is a recommendation, not an instruction to change the setting.

## Related skills

- Claude Code permissions, hooks, and sandbox → `sec-claudeCode-guardrails-manage`.
- Coding-agent prompt injection → `sec-agents-promptInjection-defend`.
- Secret storage/rotation → `sec-secrets-any-manage`.
