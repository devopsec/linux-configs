# Claude Specifics for Infra Rag Pipeline Manage

## Context & Tuning
- Read only `references/rag-pipeline.md` and vector DB material when store operations are in scope; keep tenant filters in retrieval.

## Instructions Overrides
- Bind SQL parameters; delimit retrieved context as data, not system instructions or unchecked tool authority.

## Performance Notes
- Measure retrieval and answer quality separately and include negative isolation tests.
