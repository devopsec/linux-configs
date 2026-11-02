# Junie CLI Specifics for Sec Iam Accessreview Run

## Context & Tuning
- Reconcile all human and non-human identity sources, including inherited grants, before sampling.
- Use read-only exports and owner decisions; load only the access-review checklist.

## Instructions Overrides
- Never revoke access automatically from an inventory flag; obtain authorization and check impact.

## Performance Notes
- Do not expose key material, credentials, or unnecessary personal data; do not commit review evidence.
