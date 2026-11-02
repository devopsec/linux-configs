---
name: dev-rag-evals-create
description: "Design and monitor evaluation suites for retrieval-augmented generation systems. Use when users ask for RAG metrics, recall@k, MRR, RAGAS, grounding, retrieval quality, index freshness, or RAG evaluation alerts."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - devops/ai/rag-observability-evals
  license: MIT
---

# RAG Evaluation

Evaluate retrieval, generation, and reliability separately so a score change points to a measurable failure mode.

## Triggers

- RAG evaluation datasets, retrieval ranking/coverage, groundedness, answer relevancy, or hallucination rates.
- RAGAS schemas/API, quality monitoring, index staleness, or evaluation triage.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/dev/rag-evals.toml"
  REFERENCE "~/.junie/custom/configs/dev/rag-evals.toml"
ELSE
  USE the tool defaults listed below
IF task involves RAG metrics, datasets, or monitoring
  REFERENCE "references/rag-evals.md"
CACHE only the loaded evaluation choices for this task
```

## Workflow

1. Keep a curated evaluation set plus a held-out set; include human references and stable relevant document IDs.
2. Measure recall@k/MRR without an LLM, then score generation with a pinned judge and `ragas` 0.4.3.
3. Track retrieval/generation latency, cost, fallback rate, and index version without high-cardinality user or query labels.
4. Diagnose metrics together; change thresholds or baselines only after reviewing fixtures and the underlying corpus/index change.

## Tool defaults

- Use deterministic retrieval metrics first; use `ragas==0.4.3` (checked 2026-10-28) for groundedness/relevance measures when its fields fit the pipeline.
- Keep the judge model and embedding model pinned with the application lockfile; compare like-for-like runs.
- Optional evaluator choices are illustrated in `assets/config.example.toml`; do not create global config files automatically.

## Related skills

- General agent eval design and judge calibration → `dev-agents-evals-create`.
- RAG pipeline security and tenant isolation → `sec-llm-rag-harden`.
- RAG pipeline operations → `infra-rag-pipeline-manage`.
