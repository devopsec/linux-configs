---
name: infra-gcp-vpc-manage
description: "Manage Google Cloud VPC networks, custom subnets, firewall rules, Cloud NAT, private Google access, static addresses, and load balancing with gcloud. Use when tasks mention GCP VPC, subnet CIDR, firewall rule, Cloud NAT, PSC, private service access, or network load balancer."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-gcp/gcp-networking
  license: MIT
---

# GCP VPC manage

Plan and operate GCP network resources with explicit environment and traffic requirements. Keep Terraform/OpenTofu-managed networks in IaC.

## Triggers

- VPC, custom subnet, route, Cloud NAT, Private Google Access, PSC/PSA
- VPC firewall, hierarchical firewall policy, static IP, passthrough or application load balancer

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves a VPC, subnet, firewall, NAT, static address, or load balancer
  REFERENCE "references/networking.md"
IF task involves GCE, Cloud SQL, GKE, or Cloud Run connectivity
  REFERENCE the matching GCP service skill
IF network resources are IaC-managed
  REFERENCE skill "infra-terraform-gcp-manage" OR "infra-opentofu-any-manage"
CACHE project, region, network, CIDRs, peer ranges, and target identities as runtime inputs
```

## Workflow

1. Confirm project, environment, traffic direction, source/destination identities, required protocols, and existing routes.
2. Inspect current firewall priorities, routes, NAT, and connectivity tests before editing.
3. Use custom-mode VPCs, least-privilege source ranges, service-account targets, flow logs where useful, and private API access.
4. Treat CIDRs, peer ranges, ports, and NAT IPs as user-provided inputs; never invent or persist site values.
5. Preview in IaC where applicable; state expected connectivity impact and obtain approval for production changes.
6. Verify with a GCP Connectivity Test, firewall logs, and application-level reachability.

## Related skills

- `infra-gcp-compute-manage` — VM network attachments and IAP access.
- `infra-gcp-cloudSql-manage` — PSA/PSC database connectivity.
- `infra-gcp-gke-manage` / `infra-gcp-serverless-manage` — cluster and serverless egress.
- `infra-terraform-gcp-manage` / `infra-opentofu-any-manage` — network IaC.
