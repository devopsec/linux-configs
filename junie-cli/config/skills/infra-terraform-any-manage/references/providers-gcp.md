# Provider: Google Cloud (`hashicorp/google`)

GCP-specific HCL. Generic module/state/CI/testing rules live in the other references — do not repeat them here. gcloud operations: skill `infra-gcp-any-manage`. All snippets are valid for `terraform` and `tofu`.

Contents: [Provider & auth](#provider-and-auth) · [Backend](#gcs-backend) · [APIs](#project-apis) · [Network](#network) · [Compute & MIG](#compute-engine-vm-template-mig) · [Cloud SQL](#cloud-sql-postgresql-private-ip) · [Functions + Pub/Sub](#cloud-run-functions-with-pubsub) · [IAM](#iam-patterns) · [Gotchas](#gotchas) · [Troubleshooting](#troubleshooting)

## Provider and auth

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0" # 8.9.0 latest as of 2026-10; verify latest
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
  }
}
```

- Only add `google-beta` for resources/fields that need it; set `provider = google-beta` per resource and pin it to the same version.
- Local: `gcloud auth application-default login`; impersonate a deploy SA instead of using personal rights: `export GOOGLE_IMPERSONATE_SERVICE_ACCOUNT=tf-deploy@<project>.iam.gserviceaccount.com` (needs `roles/iam.serviceAccountTokenCreator`).
- Cloud Build: run as a dedicated SA (`serviceAccount:` in `cloudbuild/*.yaml`) — ADC is automatic, no key files. GitHub/GitLab: Workload Identity Federation. Never `GOOGLE_APPLICATION_CREDENTIALS=sa.json` with long-lived keys.

## GCS backend

Syntax and locking: [State Management: Choosing a Remote Backend](state-management.md#choosing-a-remote-backend). Bootstrap the bucket outside the stack it stores:

```bash
gcloud storage buckets create "gs://${PROJECT_ID}-tfstate" --location="$REGION" \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update "gs://${PROJECT_ID}-tfstate" --versioning
```

One `prefix` per stack/env (`prefix = "isen/prod/network"`). Grant the deploy SA `roles/storage.objectAdmin` on the bucket only. For CMEK set it on the bucket (`--default-encryption-key`), not the backend's `encryption_key` (that is CSEK).

## Project APIs

```hcl
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
```

`disable_on_destroy = false` prevents a `destroy` (or removing one item) from disabling an API other stacks use.

## Network

Use the hardened module [`assets/gcp-sip-edge-network.tf`](../assets/gcp-sip-edge-network.tf): custom-mode VPC, app + SIP-edge subnets, IAP SSH, health-check ranges, SIP (UDP/TCP 5060, TLS 5061) and RTP rules restricted to peer CIDRs, Cloud NAT for the app subnet only, `prevent_destroy` static IPs for SIP edges. Firewall reasoning: `infra-gcp-any-manage` → `references/networking.md`.

Private Services Access for Cloud SQL:

```hcl
resource "google_compute_global_address" "psa" {
  name          = "${var.name_prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.network_id
}

resource "google_service_networking_connection" "psa" {
  network                 = var.network_id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]
}
```

## Compute Engine: VM, template, MIG

SIP edge VM with reserved IP (from the network module output):

```hcl
resource "google_compute_instance" "sip_edge" {
  for_each = var.sip_edges # map(object({ zone = string }))

  name         = "${var.name_prefix}-${each.key}"
  zone         = each.value.zone
  machine_type = "n2-standard-4"
  tags         = ["sip-edge", "iap-ssh"]

  boot_disk {
    initialize_params {
      image = "rhel-cloud/rhel-9"
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.sip_subnet_id
    access_config {
      nat_ip = var.sip_edge_ips[each.key]
    }
  }

  metadata = {
    enable-oslogin = "TRUE"
  }
  metadata_startup_script = file("${path.module}/startup.sh")

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  allow_stopping_for_update = true
}
```

Template + regional MIG for stateless tiers:

```hcl
resource "google_compute_instance_template" "worker" {
  name_prefix  = "${var.name_prefix}-worker-"
  machine_type = "n2-standard-2"
  tags         = ["isen-worker", "iap-ssh"]

  disk {
    source_image = "rhel-cloud/rhel-9"
    boot         = true
    auto_delete  = true
    disk_size_gb = 30
  }

  network_interface {
    subnetwork = var.app_subnet_id # no access_config => no external IP
  }

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = file("${path.module}/startup.sh")
  }

  service_account {
    email  = google_service_account.vm.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_health_check" "worker" {
  name = "${var.name_prefix}-worker-hc"
  http_health_check {
    port         = 8080
    request_path = "/healthz"
  }
}

resource "google_compute_region_instance_group_manager" "worker" {
  name               = "${var.name_prefix}-worker"
  region             = var.region
  base_instance_name = "${var.name_prefix}-worker"

  version {
    instance_template = google_compute_instance_template.worker.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.worker.id
    initial_delay_sec = 180
  }

  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3 # regional MIG: >= number of zones
    max_unavailable_fixed = 0
  }
}

resource "google_compute_region_autoscaler" "worker" {
  name   = "${var.name_prefix}-worker"
  region = var.region
  target = google_compute_region_instance_group_manager.worker.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 6
    cooldown_period = 180
    cpu_utilization {
      target = 0.65
    }
  }
}
```

Image pinning: `rhel-cloud/rhel-9` follows the family (new image ⇒ replacement on next apply). For reproducible prod, pin a specific image name or use `data "google_compute_image"` with `lifecycle { ignore_changes = [boot_disk[0].initialize_params[0].image] }` on standalone VMs.

## Cloud SQL PostgreSQL (private IP)

```hcl
resource "google_sql_database_instance" "main" {
  name                = "${var.name_prefix}-pg"
  database_version    = "POSTGRES_17" # verify latest supported
  region              = var.region
  deletion_protection = true

  settings {
    tier              = "db-custom-4-16384"
    edition           = "ENTERPRISE"
    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 100
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = var.environment == "prod" ? 30 : 7
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      ssl_mode                                      = "ENCRYPTED_ONLY" # replaces removed require_ssl
      enable_private_path_for_google_cloud_services = true
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    maintenance_window {
      day  = 7
      hour = 4
    }
  }

  depends_on = [google_service_networking_connection.psa]
}

resource "google_sql_database" "app" {
  name     = "isen"
  instance = google_sql_database_instance.main.name
}

# Preferred: IAM DB auth, no password in state
resource "google_sql_user" "vm" {
  name     = trimsuffix(google_service_account.vm.email, ".gserviceaccount.com")
  instance = google_sql_database_instance.main.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}
```

Built-in password user — keep the value out of state with a write-only argument fed by an ephemeral Secret Manager read (Terraform 1.11+ / OpenTofu 1.11+; google provider 8.x schema confirmed):

```hcl
ephemeral "google_secret_manager_secret_version" "db" {
  secret = "isen-db-password"
}

resource "google_sql_user" "app" {
  name                = "isen_app"
  instance            = google_sql_database_instance.main.name
  password_wo         = ephemeral.google_secret_manager_secret_version.db.secret_data
  password_wo_version = 1 # bump to push a rotated secret
}
```

Never `random_password` → `password` (lands in state in clear text). See [Code Patterns: write-only](code-patterns.md#write-only-arguments).

## Cloud Run functions with Pub/Sub

```hcl
resource "google_pubsub_topic" "cdr" {
  name = "cdr-events"
}

resource "google_pubsub_topic" "cdr_dlq" {
  name = "cdr-events-dlq"
}

resource "google_cloudfunctions2_function" "cdr_ingest" {
  name     = "cdr-ingest"
  location = var.region

  build_config {
    runtime     = "python313" # verify latest
    entry_point = "handle_cdr"
    source {
      storage_source {
        bucket = var.source_bucket
        object = var.source_object # zip built in Cloud Build
      }
    }
  }

  service_config {
    max_instance_count               = 20
    available_memory                 = "512Mi"
    timeout_seconds                  = 120
    service_account_email            = google_service_account.fn.email
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    max_instance_request_concurrency = 1

    secret_environment_variables {
      key        = "DB_PASSWORD"
      project_id = var.project_id
      secret     = "isen-db-password"
      version    = "latest"
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.cdr.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.invoker.email
  }
}

resource "google_cloud_run_service_iam_member" "invoker" {
  location = google_cloudfunctions2_function.cdr_ingest.location
  service  = google_cloudfunctions2_function.cdr_ingest.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.invoker.email}"
}
```

Never `member = "allUsers"` for event handlers. The trigger's Pub/Sub subscription is created by Eventarc — for a DLQ, create your own `google_pubsub_subscription` with `push_config` + `dead_letter_policy` targeting a Cloud Run service instead.

## IAM patterns

```hcl
resource "google_service_account" "vm" {
  account_id   = "${var.name_prefix}-vm"
  display_name = "ISEN VM runtime"
}

resource "google_project_iam_member" "vm" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vm.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_db" {
  secret_id = "isen-db-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.vm.email}"
}
```

- `_iam_member` = additive (safe). `_iam_binding` = authoritative per role; `_iam_policy` = authoritative for the whole resource — can lock out other principals. Avoid `google_project_iam_policy`.
- Scope to the resource (secret, bucket, topic) instead of project when possible.

## Gotchas

| Gotcha | Fix |
|--------|-----|
| `deletion_protection` (SQL, also on `google_compute_instance` in 6.x+) blocks destroy | Intentional; set false in a reviewed separate apply |
| Changing `name`/`zone`/disk image forces replacement | `create_before_destroy` + `name_prefix`; `moved` for address changes |
| `google_compute_instance` `metadata.startup-script` vs `metadata_startup_script` | Use one; the latter forces recreate on change |
| Labels drift from org policy / `goog-*` labels | `default_labels`; ignore system labels via `effective_labels` (read-only) |
| Firewall `0.0.0.0/0` on SIP or SSH | Peer CIDRs / IAP range; module validation rejects it |
| Major provider bump (7 → 8) | Separate PR, read upgrade guide, `plan` must show 0 replacements |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Error 403: ... API has not been used` | API disabled | `google_project_service`, wait, re-plan |
| `Error 409: already exists` | Created outside IaC | `import` block (1.5+) then plan |
| Cloud SQL create hangs/fails on network | PSA connection missing/ordering | `depends_on = [google_service_networking_connection.psa]` |
| `googleapi: Error 400: Invalid value for field 'resource.networkInterfaces[0].accessConfigs[0].natIP'` | IP in other region/in use | Reserve in same region; release from old VM |
| Plan wants to replace MIG template every run | Image family resolved to new image | Pin image or accept roll via `update_policy` |
| State lock stuck (GCS) | Crashed run | Confirm no run active, then `force-unlock <ID>` |
