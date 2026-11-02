# Claude specifics — sec-llm-rag-harden

- Trace tenant identity from authenticated session through retrieval, cache, logs, and deletion.
- Treat retrieved content as untrusted and keep indexing scans distinct from authorization checks.
- Avoid raw user queries and document bodies in metrics or committed fixtures.
