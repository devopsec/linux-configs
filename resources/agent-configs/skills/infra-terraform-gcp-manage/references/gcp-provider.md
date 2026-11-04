# Terraform Google provider

Use Terraform `1.17.0` and `hashicorp/google` `8.9.0` as checked 2026-10-28; provider versions are also recorded in `.terraform.lock.hcl`. Keep upgrades isolated, run the provider upgrade guide, and inspect a complete plan before apply. The provider block template is in `assets/provider.google.tf`.

## Authentication and APIs

Use Application Default Credentials locally and impersonate a deploy identity. CI should use workload identity federation or the platform’s service account, never a long-lived service-account key. Enable only the APIs the stack owns; set `disable_on_destroy = false` when shared stacks may depend on them.

```hcl
resource "google_project_service" "required" {
  for_each = toset(var.required_apis)
  project  = var.project_id
  service  = each.value

  disable_on_destroy = false
}
```

## GCS backend

Bootstrap a dedicated state bucket outside the stack that consumes it. Enable uniform bucket-level access, public access prevention, versioning, and CMEK where required; grant the deploy identity state access on this bucket only. CMEK belongs on the bucket configuration; the backend's `encryption_key` field is customer-supplied encryption key material, not CMEK.

```bash
gcloud storage buckets create "gs://${STATE_BUCKET}" --project="$PROJECT_ID" \
  --location="$STATE_LOCATION" --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning
terraform init -backend-config="bucket=${STATE_BUCKET}" -backend-config="prefix=${STATE_PREFIX}"
```

Declare `backend "gcs" {}` in the root stack and keep a unique prefix per environment/state. Do not store backend credentials in committed files.

## Network and private service access

Use custom VPCs, explicit subnets, and firewall rules with narrow sources/targets. Treat CIDRs, names, routes, and peer ranges as variables. Cloud SQL private IP requires PSA or PSC and correct dependency ordering.

```hcl
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.name_prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.psa_prefix_length
  network       = var.network_id
}

resource "google_service_networking_connection" "psa" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
```

## Compute and Cloud SQL

For VMs, use a dedicated service account with minimum IAM roles, OS Login, Shielded VM options, and no external IP by default. For stateless groups use versioned instance templates and a managed instance group update policy. Machine type, image, region, and scaling values are workload inputs.

For Cloud SQL, use `ipv4_enabled = false`, a private network, TLS-only transport, deletion protection, backups/PITR, and IAM DB authentication where supported. Use an explicit database major supported by the app. Never put a database password in ordinary Terraform state; use write-only arguments or runtime Secret Manager access.

The Cloud SQL PostgreSQL default is `POSTGRES_18` (minor `18.6` per documentation last updated 2026-10-22; checked 2026-10-28). Select a database major only after app/extension compatibility review; Cloud SQL manages minor patches.

```hcl
resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = var.instance_name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = true

  settings {
    tier              = var.database_tier
    edition           = "ENTERPRISE"
    availability_type = var.availability_type

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }

  depends_on = [google_service_networking_connection.psa]
}
```

Prefer IAM DB users. When a built-in password user is unavoidable, use the provider's write-only password arguments with a numeric secret version; ordinary `password` values are stored in state.

For stateless Compute Engine tiers, use immutable instance templates and MIG rollout policies. Use dedicated service accounts, OS Login, Shielded VM settings, and no external IP by default. Pin image IDs for production reproducibility or schedule image-family rollouts explicitly.

## BigQuery and Pub/Sub resources

Keep service resources declarative and use service-specific skills for data and message semantics. Select dataset location and retention before creation; scope dataset permissions to the dataset. Topic/subscription IAM should be scoped independently from project roles.

```hcl
resource "google_bigquery_dataset" "analytics" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  location                   = var.location
  delete_contents_on_destroy = false
}

resource "google_pubsub_topic" "events" {
  project = var.project_id
  name    = var.topic_id
}
```

`delete_contents_on_destroy` and service retention settings are data-loss controls; do not enable destructive behavior merely to simplify teardown. Review downstream consumers and IAM before plans that replace datasets or topics.

## Cloud Run functions

Cloud Run functions runtime `python313` is supported as checked 2026-10-28. Pin the runtime label and application dependencies; the managed base image receives provider updates. Use a dedicated runtime identity, internal ingress where appropriate, bounded concurrency/instances, and numeric Secret Manager versions.

```hcl
resource "google_cloudfunctions2_function" "handler" {
  project  = var.project_id
  name     = var.function_name
  location = var.region

  build_config {
    runtime     = "python313"
    entry_point = var.entry_point
    source {
      storage_source {
        bucket = var.source_bucket
        object = var.source_object
      }
    }
  }

  service_config {
    service_account_email            = var.runtime_service_account
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    max_instance_request_concurrency = var.concurrency
    max_instance_count               = var.max_instances
    timeout_seconds                  = var.timeout_seconds
  }
}
```

Use the Pub/Sub skill for delivery guarantees, retries, DLQ, and consumer idempotency. Do not make an event function public with `allUsers`.

## IAM and review

Prefer `*_iam_member` for additive grants. `*_iam_binding` is authoritative for a role; `*_iam_policy` can replace the whole policy. Grant resource-level access where possible. Avoid broad project editor/owner roles and disable-on-destroy API changes on shared projects.

Run `terraform fmt -check`, `terraform validate`, and `terraform plan -out=tfplan`; inspect all replacements, IAM changes, API disables, public exposure, and resource deletion. Use import blocks for existing unmanaged resources where supported; do not reconcile by ad-hoc console edits.

## References

- [Google provider registry](https://registry.terraform.io/providers/hashicorp/google/8.9.0/docs) — provider `8.9.0` published 2026-10-27; checked 2026-10-28.
- [Google provider authentication](https://cloud.google.com/docs/terraform/authentication) — checked 2026-10-28.
- [Cloud SQL PostgreSQL database versions](https://cloud.google.com/sql/docs/postgres/db-versions) — documentation last updated 2026-10-22; checked 2026-10-28.
- [Cloud Run functions runtime support](https://cloud.google.com/functions/docs/runtime-support) — runtime `python313` checked 2026-10-28.