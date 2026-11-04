# Claude Specifics for Infra Ops Drplan Create

## Context & Tuning
- Establish owner-approved scope, RPO/RTO, dependencies, activation authority, contacts, and test boundary.
- Load the DR reference and related recovery procedures only for affected services.

## Instructions Overrides
- Do not invent site targets; require approval for promotion, routing changes, failover, and failback.

## Performance Notes
- Report measured results and actions without committing runbooks or exposing incident secrets.
