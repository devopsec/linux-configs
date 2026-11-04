# Claude Specifics for Infra Llm Observability Manage

## Context & Tuning
- Read only `references/llm-observability.md` and configured backend choices; keep content capture disabled unless approved.

## Instructions Overrides
- Do not use high-cardinality labels or rely on unstable GenAI attributes as permanent schema.

## Performance Notes
- Summarize metrics/errors without reproducing prompt, response, or secret payloads.
