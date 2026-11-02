# Junie CLI Specifics for Infra Ml Pipeline Orchestrate

## Context & Tuning
- Load only `references/ml-pipeline-orchestration.md` and the selected orchestrator config; confirm whether managed GCP workflows or an existing scheduler are preferred.

## Instructions Overrides
- Check idempotency, retry safety, provider limits, artifact versions, and evaluation gates.

## Performance Notes
- Do not launch GPU jobs or publish artifacts without cost, data, and approval checks; redact credentials and make no commits.
