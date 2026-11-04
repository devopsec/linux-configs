# LLM app threat model and launch checklist

Derived from upstream `llm-app-security` / `ai-security-hardening` (MIT). Upstream labelled its table "OWASP 2025" but used the 2023 v1.1 numbering; remapped to the 2025 list below.

## OWASP Top 10 for LLM Applications (2025)

| # | Risk | Primary controls | Reference |
|---|---|---|---|
| LLM01 | Prompt Injection (direct + indirect) | containment of tools/data, instruction hierarchy, untrusted-content wrapping, human approval | `sec-llm-io-guard/references/input-output-controls.md` |
| LLM02 | Sensitive Information Disclosure | no secrets in context, tenant-filtered retrieval, PII/secret output scrubbing | `sec-llm-io-guard/references/input-output-controls.md`, `sec-llm-rag-harden/references/rag-and-tenancy.md` |
| LLM03 | Supply Chain | pinned models/deps, hash verification, model scanning | `sec-supplyChain-any-manage` |
| LLM04 | Data and Model Poisoning | ingestion scanning, source allowlists, provenance | `sec-llm-rag-harden/references/rag-and-tenancy.md` |
| LLM05 | Improper Output Handling | treat output as untrusted; encode per sink; schema validation; never `eval`/shell/SQL from output | `sec-llm-io-guard/references/input-output-controls.md` |
| LLM06 | Excessive Agency | least-privilege tools, per-user authz inside tools, approval for irreversible actions | `sec-llm-io-guard/references/input-output-controls.md` |
| LLM07 | System Prompt Leakage | no secrets/authz logic in prompts, canary tokens, assume disclosure | `sec-llm-io-guard/references/input-output-controls.md` |
| LLM08 | Vector and Embedding Weaknesses | per-tenant namespaces/filters, access-controlled retrieval, embedding deletion | `sec-llm-rag-harden/references/rag-and-tenancy.md` |
| LLM09 | Misinformation | grounding + citations, abstain on low confidence, groundedness evals | `sec-llm-rag-harden/references/rag-and-tenancy.md`, `dev-rag-evals-create` |
| LLM10 | Unbounded Consumption | auth, rate limits, token budgets, cost caps, input/output size limits | `sec-llm-api-harden/references/api-and-operations.md` |

## Blast-radius questions (answer before choosing filters)

1. If an attacker fully controls the model's next output, which tools can it call, with whose privileges?
2. What data can reach the context window (other users, other tenants, secrets, internal docs)?
3. Where does output go (HTML, Markdown with images/links, SQL, shell, email, webhooks, other agents)?
4. Which actions are irreversible or externally visible? Do they require a human?
5. Can untrusted content (web pages, uploads, emails, tickets, RAG docs) enter the same context as privileged tools? (lethal trifecta: private data + untrusted content + exfil channel)

## Launch checklist

```
[ ] Tools least-privilege; authorization enforced in tool code per end user; destructive actions need approval
[ ] No secrets or other tenants' data in system prompt or context; prompt assumed public
[ ] System and user content in separate roles; retrieved/tool content wrapped and labelled untrusted
[ ] Input size/structure limits; injection detector in log-only → tuned → block mode
[ ] Output encoded per sink; markdown images/links restricted to allowlisted domains; structured output schema-validated
[ ] PII/secret scrubbing on output (and on logs)
[ ] RAG ingestion scanned (malware, secrets, hidden text); retrieval filtered by tenant + ACL server-side; citations attached
[ ] Session/memory isolated per tenant and user
[ ] Auth on every endpoint; per-user rate limits; per-user token budget; per-tenant daily cost cap
[ ] Structured security logs without raw prompts by default; alerts on injection, canary hits, cost/token anomalies
[ ] Retention limits and deletion workflow covering relational DB, session store, vector store, logs, backups
[ ] Approved model allowlist; versions pinned; red-team + regression evals green in CI
```
