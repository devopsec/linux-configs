---
name: infra-gcp-gke-manage
description: "Design and operate Google Kubernetes Engine clusters and node pools with gcloud, Workload Identity, release channels, Gateway API, and private clusters. Use when requests mention GKE, `gcloud container`, Autopilot, Standard node pools, GKE Workload Identity, or GKE cluster upgrade."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/gke
  license: MIT
---

# GCP GKE manage

Manage GKE cluster architecture and operations. Prefer Terraform/OpenTofu for durable cluster resources and gcloud for inspection or approved break-glass changes.

## Triggers

- GKE, `gcloud container clusters`, Autopilot, Standard, node pool, release channel
- Workload Identity, GKE auth plugin, private control plane, Gateway API, Backup for GKE

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file exists "~/.junie/custom/configs/infra/gke.toml"
  REFERENCE "~/.junie/custom/configs/infra/gke.toml"
ELSE
  use Autopilot for stateless/general workloads; use Standard only for documented node-level, privileged, GPU, or host-network requirements
IF task involves cluster or node-pool design, identity, networking, ingress, or operations
  REFERENCE "references/gke-clusters.md"
IF task involves pod policy, RBAC, NetworkPolicy, or cert-manager
  REFERENCE skill "sec-kubernetes-cluster-harden"
IF task involves application manifests or rollout diagnostics
  REFERENCE skill "infra-kubernetes-workload-manage"
IF cluster resources are IaC-managed
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
CACHE project, region, network, control-plane CIDR, admin ranges, release channel, and workload identity
```

## Workflow

1. Confirm project, region, environment, ownership, cluster mode, release channel, and exact current control-plane/node versions.
2. Inspect current cluster/network settings, service identities, node pools, quotas, backup, and upgrade state.
3. Prefer private nodes/control plane, authorized admin networks, Workload Identity, dedicated node identities, and Shielded nodes.
4. Treat every CIDR, region, node size, cluster version, and node count as runtime input; configure upgrades in a maintenance window.
5. Preview IaC and require explicit approval for cluster create/delete, node-pool replacement, version upgrade, or network changes.
6. Verify cluster health, node readiness, add-ons, workloads, and backup restore path.

## Related skills

- `infra-kubernetes-workload-manage` — Kubernetes workload operations.
- `sec-kubernetes-cluster-harden` — cluster security baseline, scans, and cert-manager.
- `infra-gcp-vpc-manage` — VPC, NAT, firewall, and service networking.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — cluster IaC.
