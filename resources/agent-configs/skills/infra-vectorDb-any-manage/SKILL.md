---
name: infra-vectorDb-any-manage
description: "Choose and operate vector databases for production retrieval workloads, including PostgreSQL pgvector, Qdrant, and Weaviate, with schema/index tuning, tenant filters, backup, and recovery. Use when a request mentions a vector database, pgvector, HNSW, IVFFlat, Qdrant collection, Weaviate, ANN filtering, or vector snapshots."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/databases/vector-database-ops]
  license: MIT
---

# Vector database management

## Triggers

- Select or operate a persistent vector store for an application or RAG index.
- Tune ANN indexes/filters, estimate capacity, implement isolation, or restore vectors.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/infra/vectorDb.toml" exists
  REFERENCE "~/.junie/custom/configs/infra/vectorDb.toml"
ELSE
  use the defaults below and in "references/vectorDb.md"
REFERENCE "references/vectorDb.md" for provider choice, schema, tuning, or recovery
CACHE only the loaded vector database guidance
```

## Workflow

1. Capture vector count/dimensions, QPS, filter selectivity, recall target, tenancy, backup RPO/RTO, and operator skills.
2. Prefer pgvector on existing PostgreSQL for transactional joins and moderate scale; consider Qdrant for heavy filtered ANN/hybrid workloads; use Weaviate only when its schema/vectorizer model fits.
3. Match embedding dimensions and distance operator/index; test ANN recall with representative tenant filters.
4. Enforce tenant/ACL filters at query time and use RLS or equivalent isolation; keep endpoints private and authenticated.
5. Back up before schema/index changes or collection replacement; rehearse restore and verify count/recall.

## Defaults

- pgvector `0.8.7` on PostgreSQL for moderate scale and relational/RLS needs.
- Consider Qdrant `v1.20.0` or Weaviate `v1.40.2` only when measured workload and operating constraints justify a separate service.

## Safety

- Ask before dropping tables/collections, restoring over live data, or running production `REINDEX`.
- Credentials belong in managed secrets; never use anonymous public endpoints for private embeddings.
- Treat indexed text as sensitive; encrypt storage/backups and apply approved retention/deletion rules.

## Related skills

- RAG ingestion and retrieval design → `infra-rag-pipeline-manage`
- PostgreSQL/Cloud SQL administration → `infra-database-any-administer`, `infra-gcp-any-manage`
- Backup and disaster recovery → `infra-any-backupRecovery-manage`

## Reference

- Provider choice, pgvector/Qdrant/Weaviate operations, and recovery: [references/vectorDb.md](references/vectorDb.md)
- Fallback config example: [assets/config.example.toml](assets/config.example.toml)
