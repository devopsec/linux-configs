---
name: sec-llm-api-harden
description: "Harden LLM application APIs, authentication, cost controls, logs, and retention. Use when users ask about JWT/OIDC verification, token budgets, rate limits, model-provider keys, gateway limits, cost anomalies, or LLM audit retention."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/ai-security-hardening
    - security/ai/llm-app-security
  license: MIT
---

# LLM API and Operations Hardening

Apply authentication, shared quotas, data-minimizing observability, and lifecycle limits at the service boundary.

## Triggers

- LLM API authentication, OIDC/JWT claims, provider credentials, request quotas, or token/cost budgets.
- Gateway/proxy limits, security events, retention, purge jobs, or model access allowlists.

## Load order (SAD KITTI)

```sadkitti
IF task involves API authentication, budgets, logging, or retention
  REFERENCE "references/api-and-operations.md"
CACHE only the controls relevant to the endpoint and data lifecycle
```

## Workflow

1. Identify end-user and tenant identity, provider/model boundaries, data logged, and retention/deletion obligations.
2. Verify asymmetric issuer/audience-bound tokens; use short-lived workload identity and secret-manager injection for service credentials.
3. Enforce shared per-user/tenant rate limits and budgets before model calls; cap input, output, tool iterations, and time.
4. Log redacted structured security events, alert on abuse/cost changes, and test retention/purge paths before rollout.

## Related skills

- LLM input/output and tool-call controls → `sec-llm-io-guard`.
- RAG tenant isolation and deletion → `sec-llm-rag-harden`.
- LLM threat map and launch checklist → `sec-dev-threatModel-create`.
- Secret storage/rotation → `sec-secrets-any-manage`.
