---
name: infra-gcp-compute-manage
description: "Manage Google Compute Engine VMs, instance templates, managed instance groups, OS Login, IAP SSH, disks, snapshots, and host service identities with gcloud. Use when a request mentions gcloud compute, GCE, VM creation, MIG rollout, startup scripts, machine types, snapshots, or IAP."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/gcp-compute
  license: MIT
---

# GCP Compute Engine manage

Use gcloud for inspection and explicitly requested break-glass operations. Keep Terraform/OpenTofu-managed resources in IaC.

## Triggers

- `gcloud compute`, Compute Engine VM, instance template, MIG, autoscaler, startup script, disk, snapshot
- OS Login, IAP SSH, Shielded VM, machine type, serial-port output

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves Compute Engine, instance templates, MIGs, disks, or snapshots
  REFERENCE "references/compute-engine.md"
IF the VM is in IaC state
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
IF task involves GCP VPC, subnet, NAT, or firewall design
  REFERENCE skill "infra-gcp-vpc-manage"
CACHE project, region, zone, identity, and environment as user-provided runtime inputs
```

## Workflow

1. Confirm project, region/zone, environment, current context, and ownership; never infer production intent.
2. Inspect with `describe`/`list`; check IAM, quota, disks, and network path before proposing a change.
3. Prefer dedicated service accounts, least-privilege roles, OS Login, Shielded VMs, and no external IP unless explicitly required.
4. Treat startup scripts as repeatable boot-time code; fetch secrets at runtime from Secret Manager and keep SELinux enforcing.
5. For deletion, disk detach, snapshot restore, or rollout changes, show the exact target and impact and obtain explicit approval.
6. Verify instance health, rollout status, serial output, and logs after an approved change.

## Related skills

- `infra-gcp-vpc-manage` — VPC, NAT, firewall, and load balancing.
- `infra-gcp-cloudSql-manage` — managed PostgreSQL connectivity.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — infrastructure as code.
- `sec-linux-host-harden` — guest OS baseline.
