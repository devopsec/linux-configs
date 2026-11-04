---
name: infra-aws-vpc-manage
description: "Design and operate AWS VPCs, subnets, route tables, gateways, security groups, NACLs, endpoints, peering, Transit Gateway, and flow logs. Use when requests mention VPC, subnet, route table, NAT gateway, security group, VPC endpoint, peering, Transit Gateway, or Reachability Analyzer."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/cloud-aws/aws-vpc
  license: MIT
---

# AWS VPC manage

Use this skill for AWS virtual network architecture and controls. CIDRs, regions, ports, and connectivity peers are runtime inputs, not defaults to assume.

## Triggers

- Plan or modify VPC/subnet layout, routes, Internet/NAT gateways, or endpoints.
- Troubleshoot security group, NACL, peering, Transit Gateway, or private DNS connectivity.
- Configure VPC Flow Logs or Reachability Analyzer.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md if present
IF file exists "~/.junie/custom/configs/infrastructure/aws-vpc.toml"
  REFERENCE "~/.junie/custom/configs/infrastructure/aws-vpc.toml"
ELSE use the defaults listed below
IF task involves VPCs, subnets, routing, gateways, security groups, endpoints, peering, or flow logs
  REFERENCE "references/vpc.md"
CACHE only the loaded VPC guidance for this task
```

## Workflow

1. Gather account, region, environment, CIDR inventory, address-family requirements, availability zones, and connectivity peers; confirm no overlapping ranges.
2. Inspect existing routes, associations, security-group rules, NACLs, endpoints, and IaC ownership read-only. Prefer Terraform/OpenTofu for changes.
3. Use least-exposure rules, security-group references, and endpoints where appropriate. Treat public routes and broad ingress as explicit exceptions with an owner and justification.
4. Review route propagation, return paths, AZ resilience, NAT cost, and interruption risk before applying. Confirm the exact target environment for connectivity changes.
5. Validate with Reachability Analyzer, flow logs, and application-level checks; document CIDRs and ports only from user-provided inputs.

### Defaults when no config exists

- IaC: Terraform/OpenTofu; AWS CLI for read-only inspection and Reachability Analyzer.
- Production networks: redundant AZ design, no public ingress by default, and separate application/data tiers where the workload requires them.
- Ask the user for CIDRs, required ports/protocols, source peers, and site routing values; do not invent them.

## Related skills

- Compute placement → `infra-aws-ec2-manage`
- AWS service access and bucket policy → `infra-aws-iam-manage`, `infra-aws-s3-manage`
- Host firewall / VPN / TLS controls → `sec-linux-hostFirewall-manage`, `sec-network-vpn-manage`, `sec-tls-config-audit`
- IaC workflows → `infra-terraform-any-manage`, `infra-opentofu-any-manage`
