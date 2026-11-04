# Claude Specifics for Sec Gcp Auditlogs Manage

## Context & Tuning
- Follow `SKILL.md`'s SAD KITTI branches and inspect the actual audit policy and destination before changes.
- Prefer reviewed infrastructure as code; treat manual policy replacement and retention locks as high risk.
- Keep project, organization, dataset, and bucket values in approved configuration or user input.

## Instructions Overrides
- Do not apply IAM, audit-policy, or retention changes without explicit approval.

## Performance Notes
- Load only the audit type or destination reference required by the task.
