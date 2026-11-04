# GCP VPC firewall

## Model and design

- VPC firewall rules are stateful and evaluated by priority; network firewall policies may be evaluated before VPC rules depending on the network's configured order.
- Prefer service-account targets for security-sensitive workloads; network tags can be assigned by instance administrators.
- Cloud firewall rules do not replace host firewall controls. Keep management and application interfaces private by default.
- Resolve project, network, targets, source CIDRs, and ports from approved runtime inputs or the configured GCP firewall TOML; never invent them.

## IaC-first rule

Use OpenTofu/Terraform for durable policy. Keep source ranges and target identity explicit; reject broad public access to management, database, RPC, or administrative ports. Enable logging for security-relevant ingress rules.

```hcl
resource "google_compute_firewall" "approved_service" {
  name      = "<rule-name>"
  project   = var.project_id
  network   = var.network_id
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["<approved-port>"]
  }

  source_ranges           = var.approved_source_cidrs
  target_service_accounts = [var.target_service_account]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
```

Add validation that rejects unintended public source ranges, and review the plan output before apply. A source range of `0.0.0.0/0` means all IPv4 sources; never use it for SSH, database, RPC, or administrative interfaces. SIP media ranges require explicitly approved peer policy and must match the media service configuration.

## Read-only review and safe rollout

List current rules/policies and confirm evaluation order before proposing changes. Use Connectivity Tests and firewall logs to validate intended reachability. If replacing an existing rule, add and verify the approved replacement first; disable/delete the old rule only after owner approval and a rollback plan.

Firewall rule changes are auditable in GCP Admin Activity logs. Route alerting to the cloud audit-logging owner. Do not paste project identifiers, CIDRs, or full firewall dumps into public reports.