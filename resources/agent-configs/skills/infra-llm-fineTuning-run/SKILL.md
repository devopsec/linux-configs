---
name: infra-llm-fineTuning-run
description: "Plan and execute private LLM fine-tuning runs using LoRA/QLoRA, TRL, Axolotl, and multi-GPU strategies, including dataset controls, evaluation gates, artifact registration, and serving handoff. Use when a request mentions fine-tuning, SFT, LoRA, QLoRA, DPO, Axolotl, TRL, DeepSpeed, or a GPU training job."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/local-ai/llm-fine-tuning]
  license: MIT
---

# LLM fine-tuning runs

## Triggers

- Compare prompting/RAG with a supervised or preference fine-tuning run.
- Plan QLoRA/LoRA, DPO, GPU sizing, evaluation, or private model registration.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/llm-fineTuning.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/llm-fineTuning.toml"
ELSE
  use the defaults below and in "references/llm-fineTuning.md"
REFERENCE "references/llm-fineTuning.md" for method, training, or model handoff
CACHE only the loaded fine-tuning guidance
```

## Workflow

1. Use RAG for changing knowledge; fine-tune only when behavior, style, or format is the goal.
2. Verify base-model and dataset licenses, provenance, privacy classification, chat template, split, and immutable revisions.
3. Start with a small QLoRA run on a single GPU; pin Axolotl `0.21.0` or TRL `1.16.0` (checked 2026-10-28) and lock the compatible environment.
4. Keep training/eval data separate, checkpoint to private versioned storage, and compare against held-out, regression, and safety sets.
5. Register only after quality gates pass; record base revision, dataset hash, settings, metrics, and artifact digest.

## Defaults

- TRL `1.16.0` or Axolotl `0.21.0`, QLoRA SFT, one GPU for the initial small run.
- Keep model artifacts and training/evaluation data private; do not publish by default.

## Safety

- Never train on secrets or unclassified PII; de-identify approved data and restrict dataset/artifact access.
- Do not publish a model or dataset externally without explicit approval and license review.
- GPU jobs and artifact deletion require cost/target confirmation; snapshot before destructive changes.

## Related skills

- Pipeline scheduling and retries → `infra-ml-pipeline-orchestrate`
- RAG for knowledge retrieval → `infra-rag-pipeline-manage`
- Model serving and deployment → `infra-vllm-server-manage`, `infra-kserve-modelServing-manage`
- Training evaluation harnesses → `dev-agents-evals-create`

## Reference

- Method choice, QLoRA/DPO, distributed runs, evaluation, and registration: [references/llm-fineTuning.md](references/llm-fineTuning.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
