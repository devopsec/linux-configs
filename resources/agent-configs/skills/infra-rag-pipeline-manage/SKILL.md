---
name: infra-rag-pipeline-manage
description: "Design and operate retrieval-augmented generation pipelines, including document ingestion, deterministic chunking, embeddings, hybrid retrieval, reranking, citations, tenant ACLs, and quality evaluation. Use when a request mentions RAG, document indexing, chunking, embeddings, hybrid search, reranking, retrieval filters, or citations."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/local-ai/rag-infrastructure]
  license: MIT
---

# RAG pipeline management

## Triggers

- Build or debug an ingestion-to-retrieval pipeline for LLM applications.
- Improve retrieval quality, freshness, isolation, citations, or evaluation.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/rag.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/rag.toml"
ELSE
  use the defaults below and in "references/rag-pipeline.md"
REFERENCE "references/rag-pipeline.md" for ingestion, retrieval, security, or evaluation
CACHE only the loaded RAG guidance
```

## Workflow

1. Gather source systems, sensitivity, tenant/ACL model, corpus size, update cadence, latency target, and quality metric.
2. Use deterministic IDs and content hashes; version the embedding model and re-embed into a new index before switching models.
3. Start with PostgreSQL + pgvector for a modest corpus; choose a dedicated vector service only for measured scale/filter needs.
4. Apply tenant/ACL filters inside retrieval, rerank a bounded candidate set, and cite only retrieved source IDs.
5. Evaluate recall/MRR and faithfulness on a labelled set; test deletion, freshness, and cross-tenant isolation.

## Defaults

- Start with PostgreSQL/pgvector; a 400-token chunk and 60-token overlap are only a measured baseline.
- Require tenant/ACL filters at retrieval and citations tied to returned source IDs.

## Safety

- Retrieved text is untrusted data, never system instructions; do not let it invoke tools without policy checks.
- Exclude secrets and unapproved PII from indexing; use bound query parameters and row-level security where supported.
- Snapshot before destructive reindex/delete operations; approve third-party embedding/reranking data egress.

## Related skills

- Vector store schema, indexing, and backup → `infra-vectorDb-any-manage`
- Ingestion scheduling and retries → `infra-ml-pipeline-orchestrate`
- LLM serving/gateway → `infra-llm-gateway-manage`
- Prompt-injection controls → `sec-llm-app-harden`

## Reference

- RAG contracts, chunking, retrieval, security, and evaluation: [references/rag-pipeline.md](references/rag-pipeline.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
