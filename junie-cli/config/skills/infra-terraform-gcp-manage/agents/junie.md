# Junie CLI Specifics for Infra Terraform Gcp Manage

## Agent instructions

- Load provider references and the matching service skill only when needed.
- Confirm project, identity, backend, and exact provider lock before plan generation.
- Require approval for production applies, IAM changes, state surgery, or resource destruction.
