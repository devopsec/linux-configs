# Infrastructure Guidelines

Guidelines for managing infrastructure using OpenTofu, Terraform, Pulumi, and GCP.

## Primitives
- **OpenTofu/Terraform/Pulumi**: Use modular/component patterns. Keep state management in mind.
- **GCP**: Audit IAM policies. Harden Cloud Run/Functions. Use Workload Identity.

## Best Practices
- REFERENCE `~/.junie/skills/infra-opentofu-any-manage/references/quick-reference.md`
- REFERENCE `~/.junie/skills/infra-pulumi-any-manage/references/quick-reference.md`
- REFERENCE `~/.junie/skills/infra-terraform-any-manage/references/quick-reference.md`
- Always perform a `plan` before `apply`.
- Audit security groups and firewall rules for "allUsers" or "0.0.0.0/0".
