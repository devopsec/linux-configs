# Junie CLI Specifics for Infra Llm Observability Manage

## Context & Tuning
- Load only `references/llm-observability.md`; keep GenAI convention names behind a replaceable adapter and confirm backend, residency, retention, and approval.

## Instructions Overrides
- Redact before export; never use prompts, secrets, or raw IDs as labels or log fields.

## Performance Notes
- Validate cardinality, representative failures, SLO queries, and collector delivery; no commits.
