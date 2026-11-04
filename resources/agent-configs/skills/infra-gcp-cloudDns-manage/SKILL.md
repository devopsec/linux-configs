---
name: infra-gcp-cloudDns-manage
description: "Manage Google Cloud DNS zones and records, including private DNS, DNSSEC, SIP SRV/NAPTR, CAA, email authentication, and TTL migrations. Use when a task mentions gcloud dns, managed zones, DNSSEC, SRV, NAPTR, DNS records, or Cloud DNS troubleshooting."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream: [infrastructure/networking/dns-management]
  license: MIT
---

# Google Cloud DNS management

## Triggers

- Create or modify Cloud DNS public/private zones and record sets.
- Publish or troubleshoot SIP NAPTR/SRV records, DNSSEC, CAA, SPF, DKIM, or DMARC.
- Plan a DNS migration, TTL transition, or authoritative-response investigation.

## Load order (SAD KITTI)

```sadkitti
REQUIRE project DNS ownership policy and AGENTS.md if present
REFERENCE "references/cloud-dns.md"
IF records or zones are declared in OpenTofu/Terraform
  REFERENCE the IaC skill and inspect the plan before live changes
IF SIP records are involved
  REFERENCE skill "dev-kamailio-platform-manage" to confirm live transports and listeners
CACHE only the relevant record type and migration guidance
```

## Workflow

1. Confirm project, managed zone, public/private visibility, record owner, desired record set, TTL, and resolver impact.
2. Read the authoritative zone state and compare it with intended IaC and live application listeners.
3. Show the exact before/after record diff; stage multi-record changes transactionally.
4. Lower TTL ahead of planned migrations and allow prior TTL/cache windows to expire; apply only after approval.
5. Query authoritative and recursive resolvers, verify DNSSEC where enabled, and monitor the dependent service.

## Safety

- Never guess domains, IPs, SIP transports, SRV priorities, or site TTLs; ask for approved values.
- Changes to apex, NS, MX, CAA, and SIP SRV/NAPTR can cause outages; require explicit review of the exact diff.
- Protect DNS API credentials and DNS-01 challenge tokens; scope them to the zone/record where possible.

## Related skills

- SIP listener and transport configuration → `dev-kamailio-platform-manage`
- TLS certificates and CAA policy → `sec-network-tls-manage`
- DNS as code → `infra-opentofu-any-manage`, `infra-terraform-any-manage`
- Load balancing and health-check endpoints → `infra-network-loadBalancer-manage`

## References

- [references/cloud-dns.md](references/cloud-dns.md) — Cloud DNS records, SIP discovery, DNSSEC, email records, and migration checks.
