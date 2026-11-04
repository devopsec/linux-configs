# GCP VPC networking

All network names, regions, CIDRs, ports, and peer ranges are runtime inputs. Reserve and review address space before allocating subnets; never substitute example or private ranges for user values.

## VPC and subnet baseline

Use a custom-mode VPC rather than the default network. Enable Private Google Access on subnets that need Google APIs without external IPs. Enable flow logs according to the investigation and cost needs; confirm log sinks, retention, and sampling policy.

```bash
gcloud compute networks create "$VPC" \
  --project="$PROJECT_ID" --subnet-mode=custom --bgp-routing-mode=regional
gcloud compute networks subnets create "$SUBNET" \
  --project="$PROJECT_ID" --network="$VPC" --region="$REGION" \
  --range="$SUBNET_CIDR" --enable-private-ip-google-access --enable-flow-logs
```

Plan free ranges for Private Services Access, serverless connectors when required, peerings, and on-prem routes. Peering is non-transitive; Cloud SQL private access may require route export for on-prem clients.

## Firewall policy

- Rules are stateful; implied ingress deny and egress allow apply unless a policy changes them.
- Target production rules by service account where supported. Tags are mutable and can widen access if users can retag instances.
- Keep source ranges and ports as narrow as the application protocol permits. Do not open SSH or broad internal ranges to the internet.
- Permit health-check and IAP source ranges only to the exact backend/admin ports needed. Avoid high-volume flow/firewall logging unless the observability need justifies the cost.

```bash
gcloud compute firewall-rules create "$RULE_NAME" \
  --project="$PROJECT_ID" --network="$VPC" --direction=INGRESS \
  --priority="$PRIORITY" --allow="$PROTOCOL_AND_PORTS" \
  --source-ranges="$SOURCE_CIDRS" --target-service-accounts="$TARGET_SA"
```

Review hierarchical firewall policy, rule priority, target selection, and logging before adding a VPC rule. Test the intended path instead of assuming the rule is effective.

## Cloud NAT, static addresses, and load balancing

- Use Cloud NAT for outbound access from private instances that need public internet destinations. It does not provide inbound connectivity.
- Reserve static external addresses only for documented ingress or stable egress requirements; unused addresses may incur charges.
- Choose passthrough Network Load Balancing when the backend needs original client IP and L4 protocol preservation; use Application Load Balancing for HTTP(S) proxy features and supported policies.
- Validate health checks, backend firewall paths, session affinity, and failure behavior before cutover.

```bash
gcloud compute routers create "$ROUTER" --project="$PROJECT_ID" \
  --network="$VPC" --region="$REGION"
gcloud compute routers nats create "$NAT" --project="$PROJECT_ID" \
  --router="$ROUTER" --region="$REGION" --nat-all-subnet-ip-ranges
```

Do not put protocols that require a stable peer-visible address or preserve UDP session behavior behind generic NAT without an explicit protocol review.

## Private Google Access and service connectivity

Private Google Access allows resources without external IPs to reach supported Google APIs; PSC for Google APIs is an alternative when a fixed internal endpoint is required. Shared VPC subnet access must be granted to the service project identity. Verify DNS, routes, API enablement, and IAM separately.

## Diagnostics

```bash
gcloud compute firewall-rules list --project="$PROJECT_ID" --filter="network:$VPC"
gcloud compute networks subnets list --project="$PROJECT_ID" --filter="network:$VPC"
gcloud network-management connectivity-tests list --project="$PROJECT_ID"
```

**Destructive:** deleting a rule, route, NAT, subnet, or static address can interrupt service or release an address. Inspect dependencies and obtain approval before mutation.

## References

- [VPC documentation](https://cloud.google.com/vpc/docs) — checked 2026-10-28.