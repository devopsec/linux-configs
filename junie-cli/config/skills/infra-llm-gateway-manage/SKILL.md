---
name: infra-llm-gateway-manage
description: "Configure LiteLLM as a private LLM gateway with provider routing, virtual keys, budgets, fallbacks, request limits, and safe caching. Use when a request mentions LiteLLM proxy, model aliases, virtual keys, LLM rate limits, gateway fallbacks, or token-cost budgets."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/networking/llm-gateway, devops/ai/llm-caching, devops/ai/llm-cost-optimization, infrastructure/local-ai/multi-tenant-llm-hosting]
  license: MIT
---

# LLM gateway management

## Triggers

- Configure provider routes, virtual keys, budgets, fallbacks, caching, or gateway health.
- Debug LLM gateway spend, backend failures, rate limits, or streaming.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/llm-gateway.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/llm-gateway.toml"
ELSE
  use the defaults below and in "references/llm-gateway.md"
REFERENCE "references/llm-gateway.md" for LiteLLM config, policy, or operations
CACHE only the loaded gateway guidance
```

## Workflow

1. Identify gateway hosting boundary, providers, model aliases, auth source, data policy, budgets, and availability goals.
2. Use LiteLLM `v1.106.4` (checked 2026-10-28) only after verifying the release artifact; `v1.107.0` was compromised and must not be used.
3. Keep master/provider credentials in Secret Manager or an injected secret store; issue one virtual key per workload/team.
4. Validate routing/fallbacks, budget enforcement, SSE streaming, health, and tenant-isolated cache behavior before rollout.
5. Monitor spend and errors; document the route/version and safe rollback.

## Defaults

- LiteLLM `v1.106.4`, private `localhost` bind, and master/provider keys from Secret Manager.
- Prompt capture and caching are disabled until an explicit data/retention review approves them.

## Safety

- Do not expose the master key or place provider keys in config files, shell history, logs, or chat.
- Never enable prompt/response debug capture by default; cache only data permitted by retention and tenant rules.
- Verify package and image provenance: the 2026-10-21 `v1.107.0` release was malicious; rotate credentials if it was run.

## Related skills

- Ollama and vLLM backends → `infra-ollama-server-manage`, `infra-vllm-server-manage`
- LLM autoscaling → `infra-llm-scaling-manage`
- LLM telemetry and redaction → `infra-llm-observability-manage`
- Secret storage and rotation → `sec-secrets-any-manage`

## Reference

- LiteLLM routes, keys, budgets, cache, and incident handling: [references/llm-gateway.md](references/llm-gateway.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
