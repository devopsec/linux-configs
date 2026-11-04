# Claude Specifics for Sec Iam Accessreview Run

## Context & Tuning
- Reconcile identity sources and effective inherited access before sampling; record gaps in source coverage.
- Use approved read-only exports and obtain owner/reviewer decisions for each access change.

## Instructions Overrides
- Do not revoke access automatically or include credentials, key material, or unnecessary personal data.

## Performance Notes
- Summarize population, decisions, exceptions, and completion status; do not commit review evidence.
