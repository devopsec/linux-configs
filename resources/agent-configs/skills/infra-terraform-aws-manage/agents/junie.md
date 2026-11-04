# Junie CLI Specifics for Infra Terraform Aws Manage

## Agent instructions

- Confirm account, region, execution role, and state backend before planning.
- Keep credentials in SSO/OIDC providers and never put key values in HCL or variable files.
- Review IAM, public exposure, and replacement actions; request approval before apply.
