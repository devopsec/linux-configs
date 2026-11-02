# RAG pipeline security and tenant isolation

Derived from upstream `llm-app-security` (MIT). Rewritten PostgreSQL/pgvector-first (our stack); Pinecone/Weaviate/Redis examples condensed to principles.

## Ingestion (LLM04 poisoning, LLM02 disclosure)

- Source allowlist: only ingest from approved buckets/systems; record `source_uri`, `ingested_at`, `ingested_by`, content hash.
- Scan every document before chunking: malware (ClamAV `clamscan --no-summary <file>`), secrets (gitleaks/detect-secrets on extracted text), PII classification (Presidio / Cloud DLP) → redact or route to restricted index.
- Strip hidden content: HTML comments, invisible CSS text, zero-width/bidi characters, alt-text payloads, PDF annotations; keep a rendered-text view for review.
- Quarantine suspicious docs (instruction-like phrasing aimed at AI, URLs with templated query params) for human review rather than silently dropping.

## Access-controlled retrieval (LLM08)

Filter **in the query**, server-side, from the authenticated session — never trust tenant/role values coming from the model or the client body.

```sql
-- pgvector: tenant + ACL filter applied before ranking
CREATE TABLE chunks (
  id bigserial PRIMARY KEY,
  tenant_id uuid NOT NULL,
  acl_groups text[] NOT NULL,
  source_uri text NOT NULL,
  content text NOT NULL,
  embedding vector(<dim>) NOT NULL
);
ALTER TABLE chunks ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON chunks
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
-- per request (in a transaction): SET LOCAL app.tenant_id = '<from session>';
SELECT id, source_uri, content
FROM chunks
WHERE acl_groups && $1::text[]            -- caller's groups from session
ORDER BY embedding <=> $2                 -- query embedding
LIMIT 5;
```

- RLS makes a forgotten `WHERE tenant_id` fail closed. The app role must not be table owner or have `BYPASSRLS`.
- Managed vector DBs: one namespace/collection (or tenant shard) per tenant **plus** metadata filters; never rely on metadata filters alone for hard isolation.
- Return chunk provenance (`source_uri`, version) with every answer → citations (LLM09) and audit.

## Session, memory, and cache isolation

- Conversation history keyed by `tenant_id:user_id:session_id`; verify ownership on every read; TTL on sessions.
- Long-term memory/summaries are tenant data — same isolation and deletion rules as documents.
- Prompt/semantic caches must include tenant (and ACL scope) in the cache key, or cross-tenant leakage follows.
- Never share a single conversation context across users (e.g. batched requests) without strict separation.

## Deletion and GDPR (right to erasure)

Erase across all stores, and prove it:

1. Relational rows (PostgreSQL / Cloud SQL) for the subject.
2. Vector chunks/embeddings derived from their documents or messages (`DELETE FROM chunks WHERE … RETURNING id` and log counts).
3. Session/memory stores and caches.
4. Logs and analytics (BigQuery: partitioned tables with expiration; targeted `DELETE` for subject data where retention is longer).
5. Backups: documented expiry window instead of in-place edits.
6. Fine-tuned models trained on the data: record lineage; retraining policy.

Write an audit record of the deletion (who, when, counts per store) without the deleted content.

## RAG-specific red-team cases

Poisoned doc with instructions to the assistant; doc from tenant B retrievable by tenant A query; citation pointing to a source the user can't access; stale doc after deletion still retrieved (cache/index lag).
