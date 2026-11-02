# Claude specifics — infra-aws-lambda-manage

- Load only the relevant Lambda reference; keep service-specific IAM with the IAM skill.
- Present deployment impact, event behavior, and rollback before an apply action.
- Never expose payload secrets or commit changes.
