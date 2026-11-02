# Junie CLI Specifics for Infra Kserve Modelserving Manage

## Context & Tuning
- Follow the KServe config hook and load only `references/kserve.md`; confirm cluster version, deployment mode, runtime, artifact URI, and GPU quota.

## Instructions Overrides
- Do not change public ingress, route weights, or replica ceilings without explicit authorization.

## Performance Notes
- Gate promotion on readiness, SLOs, and evaluation; preserve a previous model revision for rollback. Redact credentials and make no commits.
