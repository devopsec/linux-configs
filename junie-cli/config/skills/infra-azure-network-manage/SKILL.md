---
name: infra-azure-network-manage
description: "Design and manage Azure VNets, subnets, NSGs/ASGs, NAT Gateway, peering, private endpoints/DNS, Azure Firewall, Application Gateway, load balancing, and Network Watcher. Use when requests mention VNet, NSG, route table, NAT Gateway, private endpoint, hub-spoke, Azure Firewall, WAF, or Network Watcher."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-azure/azure-networking
  license: MIT
---

# Azure network manage

Use this skill for Azure virtual networking and managed network controls. CIDRs, ports, regions, and peer networks are runtime inputs, not defaults to assume.

## Triggers

- Design or troubleshoot VNets, subnets, peering, routing, or private DNS.
- Configure NSGs/ASGs, NAT Gateway, Private Link, Azure Firewall, or Application Gateway/WAF.
- Diagnose flows with Network Watcher or set up network flow logs.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/azure-network.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/azure-network.toml"
ELSE use the defaults listed below
IF task involves VNets, NSGs, NAT, peering, private endpoints/DNS, firewall, or load balancing
  REFERENCE "references/networking.md"
CACHE only the loaded network guidance for this task
```

## Workflow

1. Confirm subscription, region, environment, address inventory, peer ownership, protocol/port requirements, and resource ownership.
2. Inspect effective routes, NSGs, DNS, peering state, and existing firewall/NAT paths read-only. Prefer Terraform/OpenTofu for changes.
3. Design private-by-default connectivity, explicit egress, non-overlapping address spaces, least-privilege NSGs, and correct return paths.
4. Review public exposure, asymmetric routing, availability, throughput, and cost. Obtain explicit confirmation before changing production ingress, egress, or peer connectivity.
5. Validate effective routes/NSGs and test connectivity from the actual source; keep all site-specific addresses and ports sourced from the user or approved config.

### Defaults when no config exists

- Azure CLI `2.91.0` and AzureRM provider `5.11.0` (checked 2026-10-28); pin provider/module versions in the IaC source.
- Terraform/OpenTofu; use Azure CLI/Network Watcher for read-only inspection and path validation.
- Ask for CIDRs, peers, required ports, egress policy, and private DNS ownership when absent.

## Related skills

- Azure VM placement → `infra-azure-vm-manage`
- Azure SQL private endpoints → `infra-azure-sql-manage`
- IaC and AVM workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`, `infra-terraform-avmModule-develop`
- VPN/TLS and host firewall controls → `sec-network-vpn-manage`, `sec-tls-config-audit`, `sec-linux-hostFirewall-manage`
