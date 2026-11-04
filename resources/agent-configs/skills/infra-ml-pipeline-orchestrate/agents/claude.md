# Claude Specifics for Infra Ml Pipeline Orchestrate

## Context & Tuning
- Read the selected orchestrator reference and preserve existing DAG/flow conventions; keep task inputs versioned and idempotent.

## Instructions Overrides
- Never put credentials in parameters or code; confirm retry/concurrency bounds and partial-failure behavior.

## Performance Notes
- Require evaluation acceptance and artifact rollback before model deployment handoff.
