---
name: infra-vllm-server-manage
description: "Deploy and tune vLLM for GPU-backed, OpenAI-compatible LLM inference on a private VM or container host. Use when a request mentions vLLM, `vllm serve`, `vllm bench`, tensor parallelism, KV cache, LoRA serving, or GPU inference throughput."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/local-ai/vllm-server, devops/orchestration/model-serving-kubernetes]
  license: MIT
---

# vLLM server management

## Triggers

- Configure a vLLM process or immutable container for a private inference endpoint.
- Tune GPU memory, batch/concurrency, quantization, or model loading.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/vllm.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/vllm.toml"
ELSE
  use the defaults below and in "references/vllm.md"
REFERENCE "references/vllm.md" for install, deployment, tuning, or diagnosis
CACHE only the loaded vLLM guidance
```

## Workflow

1. Capture model/revision, GPU type/count, context length, traffic profile, latency target, and endpoint boundary.
2. Pin vLLM `v0.32.0` (checked 2026-10-28), match its CUDA/driver requirements, and mirror verified images where appropriate.
3. Bind privately, source keys from a secret manager, and pre-stage model weights at an immutable revision.
4. Set memory/concurrency flags from measured capacity; benchmark TTFT, inter-token latency, and throughput.
5. Roll out with a health check and rollback to the previous image/model revision.

## Defaults

- vLLM `v0.32.0`; bind to `localhost`/private network and use a pinned image/model revision.
- Start with one warm replica; set GPU, context, and concurrency limits from measured capacity.

## Safety

- Never expose a raw vLLM server to the public internet; put authentication and rate limits at the gateway.
- Treat model artifacts and custom code as untrusted until provenance and license are reviewed.
- GPU and node changes incur cost; obtain approval before provisioning or scaling capacity.

## Related skills

- Ollama single-host serving → `infra-ollama-server-manage`
- KServe model deployment on Kubernetes → `infra-kserve-modelServing-manage`
- LLM routing and policy → `infra-llm-gateway-manage`
- GPU autoscaling → `infra-llm-scaling-manage`

## Reference

- vLLM install, runtime flags, and troubleshooting: [references/vllm.md](references/vllm.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
