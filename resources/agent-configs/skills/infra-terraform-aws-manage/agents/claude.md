# Claude Specifics for Infra Terraform Aws Manage

## Agent instructions

- Confirm account, region, execution role, and state backend before a plan.
- Keep AWS credentials in SSO/OIDC providers; review IAM and public exposure in the plan.
- Require approval before production apply, RDS changes, or resource deletion.
