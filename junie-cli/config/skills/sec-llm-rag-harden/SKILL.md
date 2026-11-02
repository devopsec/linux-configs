---
name: sec-llm-rag-harden
description: "Secure retrieval-augmented generation ingestion, retrieval, memory, and deletion. Use when users ask about poisoned documents, tenant isolation, vector search ACLs, RAG PII scanning, cross-tenant leakage, or erasure across embeddings and caches."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/ai/llm-app-security
  license: MIT
---

# RAG Security Hardening

Protect every RAG stage from poisoned input, unauthorized retrieval, stale access, and incomplete deletion.

## Triggers

- RAG or vector ingestion, document scanning, tenant/ACL filters, embeddings, session memory, or deletion.
- A user reports cross-tenant retrieval, poisoned context, hidden document instructions, or stale deleted content.

## Load order (SAD KITTI)

```sadkitti
IF file exists "~/.junie/custom/configs/security/llm-rag.toml"
  REFERENCE "~/.junie/custom/configs/security/llm-rag.toml"
ELSE
  USE the scanner and isolation defaults listed below
IF task involves RAG ingestion, retrieval, sessions, or deletion
  REFERENCE "references/rag-and-tenancy.md"
CACHE only the data-flow and tenant controls relevant to the task
```

## Workflow

1. Map ingestion sources, chunk/index stores, authenticated identity, query filters, memory/cache, logs, and deletion paths.
2. Allowlist sources; scan for malware, secrets, PII, and hidden/instruction-like content before indexing; quarantine suspicious documents.
3. Enforce tenant and ACL filters server-side before ranking; isolate sessions and cache keys by tenant and user.
4. Trace deletion through relational rows, vectors, caches, logs, backups, and derived models; verify counts without logging deleted content.

## Scanner and isolation defaults

- Use malware scanning plus secret/PII classification on extracted text; configure tools from the optional TOML file.
- Start with PostgreSQL row-level security and a non-owner app role where applicable; managed vector namespaces still need metadata ACL filters.
- Keep provenance with each chunk and citations; use `gitleaks` 8.30.1 (checked 2026-10-28) when selecting that scanner.
- Optional scanner choices are illustrated in `assets/config.example.toml`; do not create global config files automatically.

## Related skills

- LLM evaluation and retrieval metrics → `dev-rag-evals-create`.
- Input/output and tool-call controls → `sec-llm-io-guard`.
- API budgets and retention operations → `sec-llm-api-harden`.
- LLM threat map → `sec-dev-threatModel-create`.
