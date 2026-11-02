# Claude specifics — dev-github-actions-manage

## Context & Tuning
- Load only relevant workflow/security guidance and read all triggering events before suggesting edits.
- Keep event data out of shell interpolation and constrain workflow/job `permissions`.
- Pin action references to reviewed immutable SHAs and retain approval boundaries for deployments.
- Never expose tokens, environment secrets, or private runner registration data.
