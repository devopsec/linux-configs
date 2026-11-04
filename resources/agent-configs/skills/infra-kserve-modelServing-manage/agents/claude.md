# Claude Specifics for Infra Kserve Modelserving Manage

## Context & Tuning
- Read only `references/kserve.md`; retain the user's RawDeployment/Serverless choice and keep CRD/controller versions aligned.

## Instructions Overrides
- Ask before production rollout, traffic split, GPU increase, or destructive deletion.

## Performance Notes
- Include rollback criteria and redact private model URIs or credentials in summaries.
