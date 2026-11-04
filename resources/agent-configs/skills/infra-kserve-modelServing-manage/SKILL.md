---
name: infra-kserve-modelServing-manage
description: "Deploy and operate model inference services with KServe on Kubernetes, including InferenceService runtimes, storage access, readiness, traffic canaries, promotion, and rollback. Use when a request mentions KServe, `InferenceService`, `serving.kserve.io`, KServe RawDeployment, or KServe canary rollout."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [devops/orchestration/model-serving-kubernetes]
  license: MIT
---

# KServe model serving

## Triggers

- Create or change KServe `InferenceService` resources or supported runtimes.
- Diagnose KServe readiness, model storage, rollout, or rollback behavior.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/kserve.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/kserve.toml"
ELSE
  use the defaults below and in "references/kserve.md"
REFERENCE "references/kserve.md" for KServe installation, manifests, or rollout work
CACHE only the loaded KServe guidance
```

## Workflow

1. Confirm Kubernetes version, KServe installation mode, model format/runtime, GPU class, artifact URI, and traffic policy.
2. Pin KServe `v0.21.0` for CRDs and controller (checked 2026-10-28); keep their versions aligned.
3. Use a least-privilege workload identity for private model storage; pin model revisions and image digests.
4. Deploy with health probes, resource requests/limits, and network restrictions; validate model readiness before routing traffic.
5. Promote only after latency/error and answer-quality gates pass; retain an explicit rollback target.

## Defaults

- KServe `v0.21.0` with `RawDeployment`, private model storage, and immutable runtime/model revisions.
- Example replica range is `1`–`4`; confirm GPU quota, mode, and traffic targets before production use.

## Safety

- Do not enable public ingress by default; route through the authenticated LLM gateway.
- Canary percentages and GPU replica counts are runtime decisions; ask for targets rather than inventing production values.
- Treat model pulls, replica changes, and deletion as cost-affecting or destructive operations.

## Related skills

- vLLM runtime operations → `infra-vllm-server-manage`
- Generic Kubernetes workloads and policy → `infra-kubernetes-any-manage`
- LLM autoscaling → `infra-llm-scaling-manage`
- Serving evaluation gates → `dev-agents-evals-create`

## Reference

- KServe install, manifests, rollout, and operations: [references/kserve.md](references/kserve.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
