# Retrieval-augmented generation pipeline

## Architecture and contracts

```text
source → loader → deterministic chunker → embedder → vector store + metadata/ACL
question → embed/rewrite → filtered retrieval → rerank → LLM gateway → answer + citations
```

Store per chunk: deterministic ID, document ID, chunk index, content, source URI, title/section, document hash, embedding model/revision, tenant, ACL, and creation/version metadata. Define deletion and re-embedding behavior before indexing production data.

| Content | Starting approach |
|---|---|
| Prose/docs | Recursive chunking around 300–500 tokens with modest overlap; measure recall. |
| Markdown/runbooks | Split on headings first; retain heading path as metadata. |
| Code/config | Split by language syntax or function/route boundary; preserve file and symbol metadata. |
| Tables/PDFs | Preserve row headers/page numbers with a layout-aware parser. |

Token counts should use the selected embedding model's tokenizer. Keep chunking deterministic and version its configuration.

## Ingestion and embedding

- Use `doc_hash` to skip unchanged documents; derive chunk IDs from document identity, chunk index, and embedding model revision.
- On source update, replace the old document's chunks transactionally or through a replay-safe versioned swap. Source deletion must remove its indexed chunks.
- Store the embedding model and dimension in index metadata. Re-embedding means a new column/collection plus backfill and controlled switch; do not mix vector dimensions/models in one index.
- Batch embedding requests within provider quotas; use local Ollama embeddings for development or Vertex AI in an approved region for managed GCP processing, based on sensitivity, latency, and licensing.
- Store the exact model ID and immutable model revision where supported; keep hosted model choice and region in TOML rather than hardcoded source.

## Retrieval, reranking, and citations

Start with a bounded candidate set (for example, 20–50), apply tenant/ACL filters inside the database query, then rerank a smaller set before generation. Hybrid dense + lexical search can help exact names and identifiers. Tune `k`, chunk size, and reranker using labelled recall@k/MRR and answer-quality measures rather than intuition.

PostgreSQL/pgvector can combine dense candidates and full-text candidates with reciprocal-rank fusion (RRF). Filter both candidate sets by tenant/ACL and bind all user values:

```sql
WITH dense AS (
  SELECT id, row_number() OVER (ORDER BY embedding <=> $1::vector) AS rank
  FROM chunks WHERE tenant_id = $2 AND acl && $4::text[]
  ORDER BY embedding <=> $1::vector LIMIT 40
), lexical AS (
  SELECT id, row_number() OVER (ORDER BY ts_rank_cd(content_tsv, q) DESC) AS rank
  FROM chunks, websearch_to_tsquery('english', $3) q
  WHERE tenant_id = $2 AND acl && $4::text[] AND content_tsv @@ q
  ORDER BY ts_rank_cd(content_tsv, q) DESC LIMIT 40
)
SELECT c.id, c.content, c.source_uri,
       coalesce(1.0 / (60 + d.rank), 0) + coalesce(1.0 / (60 + l.rank), 0) AS rrf
FROM chunks c
LEFT JOIN dense d ON d.id = c.id
LEFT JOIN lexical l ON l.id = c.id
WHERE c.tenant_id = $2 AND (d.id IS NOT NULL OR l.id IS NOT NULL)
ORDER BY rrf DESC LIMIT 20;
```

All SQL filters must be bound parameters, never string interpolation. Return stable source IDs/URIs with each hit; require citations to map to retrieved source IDs and reject unknown citations. Keep context delimited in a user/data section, not elevated into system instructions.

## Security and evaluation

- Retrieved documents are untrusted input and may contain prompt injection. Treat them as data; never let them authorize tools or override policy.
- Exclude secrets and unapproved PII before embedding. Validate deletion, retention, tenant isolation, ACL revocation, and data-egress behavior.
- Evaluate retrieval and generation separately: recall@k/MRR, faithfulness, answer relevance, context precision, citation validity, latency, and cost.
- Run regression tests after changes to parsing, chunking, embedding revision, filtering, prompt, or reranker. Test cross-tenant isolation with negative cases.

Vector schema/index tuning and restore procedures belong to `infra-vectorDb-any-manage`; scheduling ingestion belongs to `infra-ml-pipeline-orchestrate`.