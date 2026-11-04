---
name: infra-llm-scaling-manage
description: "Scale Kubernetes-hosted LLM inference and queued batch jobs with KEDA, Prometheus signals, and GPU-aware replica limits. Use when a request mentions KEDA, `ScaledObject`, `ScaledJob`, vLLM queue depth, KV-cache pressure, GPU inference autoscaling, or cold starts."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/local-ai/llm-inference-scaling, infrastructure/local-ai/multi-tenant-llm-hosting]
  license: MIT
---

# LLM inference scaling

## Triggers

- Add or tune KEDA online inference or queue-driven batch workers.
- Diagnose GPU scheduling, cold starts, spot capacity, or scale-out signals.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/llm-scaling.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/llm-scaling.toml"
ELSE
  use the defaults below and in "references/llm-scaling.md"
REFERENCE "references/llm-scaling.md" for KEDA triggers, capacity, or scale operations
CACHE only the loaded scaling guidance
```

## Workflow

1. Classify service as latency-sensitive online inference or retryable batch work; capture SLO, queue, GPU, and budget limits.
2. Use KEDA `v2.21.0` (checked 2026-10-28) and a measured signal such as queue depth or KV-cache pressure, not GPU utilization alone.
3. Keep at least one online replica warm; permit scale-to-zero only for batch jobs with durable queues and idempotent workers.
4. Set explicit min/max, cooldown, timeouts, PDBs, and spot/on-demand policy; check regional GPU quota.
5. Load-test scale-up/down and interruption recovery before enabling production traffic.

## Defaults

- KEDA `v2.21.0`; keep one online replica warm and set the maximum from quota/cost.
- Scale batch work to zero only with a durable queue, bounded retries, and idempotent output.

## Safety

- Obtain approval and show estimated spend before creating GPU pools or raising replica ceilings.
- Prevent unbounded queues and cross-tenant cache reuse; the gateway owns tenant identity and request quotas.
- Avoid spot-only online capacity; define graceful termination, retry, and on-demand fallback.

## Related skills

- KServe model deployments → `infra-kserve-modelServing-manage`
- LLM gateway budgets and tenant policy → `infra-llm-gateway-manage`
- Kubernetes workload controls → `infra-kubernetes-any-manage`

## Reference

- KEDA signals, online/batch scaling, GPU capacity, and validation: [references/llm-scaling.md](references/llm-scaling.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
