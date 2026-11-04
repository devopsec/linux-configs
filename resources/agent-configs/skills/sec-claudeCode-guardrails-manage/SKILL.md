---
name: sec-claudeCode-guardrails-manage
description: "Review Claude Code permissions, hooks, managed settings, and sandbox controls. Use when users mention Claude Code settings.json, permissions, PreToolUse hooks, headless CI, bypass permissions, or safe repository onboarding."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/ai-coding-agent-guardrails
  license: MIT
---

# Claude Code Guardrails Management

Use Claude Code's enforced permission, hook, and sandbox mechanisms; do not treat `CLAUDE.md` prose as an enforcement boundary.

## Triggers

- Claude Code permission rules, settings precedence, hooks, managed controls, or sandbox behavior.
- Headless Claude Code runs or secure onboarding of a repository containing `.claude/` configuration.

## Load order (SAD KITTI)

```sadkitti
IF task involves Claude Code settings, permissions, or hooks
  REFERENCE "references/claude-code.md"
CACHE only the security-relevant settings and decisions
```

## Workflow

1. Check effective settings sources with `/status` and inspect relevant rules with `/permissions` before proposing changes.
2. Prefer deny/ask boundaries and the OS sandbox over broad allow lists; review hooks as privileged code.
3. Keep project settings from escalating managed/user-only modes; restrict headless tools and provide no push or production credentials.
4. Show proposed edits as a diff and require explicit approval for permission or hook changes.

## Related skills

- Junie CLI allowlist, sandbox, and shared CI guardrails → `sec-junie-guardrails-manage`.
- Coding-agent prompt injection and untrusted repositories → `sec-agents-promptInjection-defend`.
- Agent evaluations and baselines → `dev-agents-evals-create`.
