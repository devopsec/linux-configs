# Junie specifics — sec-llm-rag-harden

- Map identity, ingestion, retrieval, memory/cache, and deletion paths before recommending filters.
- Require server-side tenant/ACL enforcement and verify negative cases without exposing tenant data.
- No commits; keep real document content and secrets out of reports.
