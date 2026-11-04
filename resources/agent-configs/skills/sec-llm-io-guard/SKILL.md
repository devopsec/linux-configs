---
name: sec-llm-io-guard
description: "Harden LLM application inputs, prompts, tool calls, and output sinks. Use when users ask about prompt injection controls, tool-call authorization, canary leakage, PII scrubbing, output encoding, or LLM guardrail frameworks."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/llm-app-security
    - security/ai/prompt-injection-defense
    - security/ai/ai-security-hardening
  license: MIT
---

# LLM Input and Output Guardrails

Contain the blast radius of an untrusted model output before adding filters. Detection heuristics are telemetry, not an authorization boundary.

## Triggers

- LLM prompt/input validation, tool/function-call policy, system-prompt leakage, or output encoding.
- PII and secret redaction, canary tokens, or guardrail framework selection.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/security/llm-io.toml"
  REFERENCE "~/.junie/custom/configs/security/llm-io.toml"
ELSE
  USE the control defaults listed below
IF task involves prompt/tool/input/output controls
  REFERENCE "references/input-output-controls.md"
CACHE only the loaded controls relevant to the application path
```

## Workflow

1. Map untrusted sources, sensitive data, tool privileges, and output sinks; ask blast-radius questions before choosing filters.
2. Enforce size/schema limits, role separation, server-side tool allowlists, and end-user authorization first.
3. Encode output for each sink; scrub PII/secrets in user-visible output and logs; require approval for irreversible actions.
4. Add adversarial and cross-tenant tests; start pattern detectors in log-only mode and tune before blocking.

## Control defaults

- Structural limits and parameter allowlists are controls; regex/classifier matches are signals only.
- Prefer self-hosted PII handling or an approved Cloud DLP path; pin app dependencies in its lockfile and evaluate upgrades.
- Keep secrets and authorization rules out of prompts; treat retrieved text and tool output as untrusted.
- Optional control selections are illustrated in `assets/config.example.toml`; do not create global config files automatically.

## Related skills

- LLM threat assessment and OWASP risk map → `sec-dev-threatModel-create` (`references/llm-app-threat-model.md`).
- RAG ingestion and tenant isolation → `sec-llm-rag-harden`.
- API budgets and operations → `sec-llm-api-harden`.
- MCP server-side tool controls → `sec-mcp-server-harden`.
- Coding-agent prompt injection → `sec-agents-promptInjection-defend`.
