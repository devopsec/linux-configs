---
name: infra-ml-pipeline-orchestrate
description: "Design and operate reproducible ML/LLM pipelines with Prefect, Airflow, Dagster, or GCP-native jobs, including ingestion, batch inference, training, evaluation, and artifact handoff. Use when a request mentions Prefect flow, Airflow DAG, Dagster asset, Cloud Composer, Vertex AI Pipelines, or ML job scheduling."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [devops/ai/ai-pipeline-orchestration]
  license: MIT
---

# ML pipeline orchestration

## Triggers

- Choose or operate an orchestrator for ingestion, training, evaluation, or batch inference.
- Make pipeline reruns, retries, concurrency, and artifact promotion reliable.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/ml-pipeline.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/ml-pipeline.toml"
ELSE
  use the defaults below and in "references/ml-pipeline-orchestration.md"
REFERENCE "references/ml-pipeline-orchestration.md" for orchestrator selection or pipeline implementation
CACHE only the loaded orchestration guidance
```

## Workflow

1. Separate ingestion, training, evaluation, and deployment; define versioned artifact contracts between stages.
2. Choose GCP-native jobs for a few event/scheduled pipelines, Prefect for Python-first flows, Airflow for established DAG estates, or Dagster for asset lineage.
3. Make tasks idempotent, retries bounded, concurrency quota-aware, and secrets available only through managed secret backends.
4. Emit per-run counts, failures, token/cost, and duration; enforce evaluation thresholds before publishing/deploying.
5. Test rerun, partial failure, duplicate delivery, and rollback paths before scheduling production runs.

## Defaults

- Use GCP-native workflows/jobs for a few scheduled/event-driven jobs; Prefect `3.9.0` for Python-first flows.
- Existing Airflow `3.3.2` or Dagster `1.13.27` estates stay on their pinned orchestrator and compatible provider set.

## Safety

- Treat pipeline parameters and retrieved data as untrusted; do not store credentials in DAGs, task params, or logs.
- Use versioned private datasets/artifacts and explicit retention; ask before external publication.
- GPU jobs cost money; state resource estimates and require approval before launch.

## Related skills

- Fine-tuning runs → `infra-llm-fineTuning-run`
- RAG ingestion/retrieval → `infra-rag-pipeline-manage`
- Vector storage operations → `infra-vectorDb-any-manage`
- GCP/Kubernetes resources → `infra-gcp-any-manage`, `infra-kubernetes-any-manage`

## Reference

- Orchestrator choice, reliable DAG/flow patterns, and GCP-native options: [references/ml-pipeline-orchestration.md](references/ml-pipeline-orchestration.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
