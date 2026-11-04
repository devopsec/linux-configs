---
name: infra-terraform-gcp-manage
description: "Create, review, and troubleshoot Terraform HCL for Google Cloud using the Google provider, ADC/workload identity, VPC, Compute Engine, Cloud SQL, BigQuery, Pub/Sub, and Cloud Run resources. Use when a request mentions Terraform plus GCP, `hashicorp/google`, `google_*` resources, or GCS-backed Terraform state."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/terraform-gcp
  license: MIT
---

# Terraform GCP provider manage

Provider-specific HCL patterns for Google Cloud. Use the generic Terraform core skill for module design, state, testing, and CI.

## Triggers

- Terraform with Google Cloud, `hashicorp/google`, `google_*` resources
- GCS backend, Workload Identity/ADC, GCP APIs, VPC/PSA, Cloud SQL, BigQuery, Pub/Sub

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or infrastructure README if present
IF task uses GCP provider resources or credentials
  REFERENCE "references/gcp-provider.md"
  REFERENCE "assets/provider.google.tf"
IF task requires generic state, module, test, or CI design
  REFERENCE skill "infra-terraform-any-manage"
IF task uses OpenTofu commands or encryption features
  REFERENCE skill "infra-opentofu-any-manage"
IF task asks for direct gcloud service operations rather than HCL
  REFERENCE the matching infra-gcp-* service skill
CACHE project, region, backend, identity, and provider lockfile versions
```

## Workflow

1. Capture exact Terraform CLI/provider versions, project, execution identity, backend, environment, and resource ownership.
2. Prefer ADC or service-account impersonation locally and workload identity federation in CI; never put JSON keys or credentials in HCL.
3. Use additive IAM members, explicit resource scopes, private networking, and write-only secret arguments where supported.
4. Keep region, CIDR, names, peer ranges, IDs, and capacity as typed inputs; never reuse values from examples as live settings.
5. Run `terraform fmt -check`, `terraform validate`, and a saved plan; review replacements, IAM, API disabling, and data-loss risk.
6. Require approval before production apply, state surgery, or destructive lifecycle changes; record rollback/recovery evidence.

## Related skills

- `infra-terraform-any-manage` — shared Terraform workflow, state, testing, and CI.
- `infra-opentofu-any-manage` / `infra-opentofu-migration-run` — OpenTofu runtime and migration.
- `infra-gcp-compute-manage`, `infra-gcp-vpc-manage`, `infra-gcp-cloudSql-manage` — gcloud operations and service behavior.
- `infra-gcp-bigquery-manage`, `infra-gcp-pubsub-manage`, `infra-gcp-serverless-manage` — service semantics.
- `sec-dev-threatModel-create` — threat-model high-impact cloud architecture changes.
