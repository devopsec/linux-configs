---
name: sec-tls-acme-manage
description: "Manage ACME certificate issuance, renewal, deployment hooks, and renewal monitoring using Certbot and compatible ACME clients. Use when a task mentions Let's Encrypt, ACME, certbot, HTTP-01, DNS-01, certificate renewal, deploy hooks, or short-lived public TLS certificates."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/ssl-tls-management
  license: MIT
---

# ACME certificate management

Issue and renew public server certificates through ACME with unattended validation, least-privilege DNS access, safe deploy hooks, and explicit expiry monitoring.

## Triggers

- Let's Encrypt, ACME, Certbot, HTTP-01, DNS-01, renewal, deploy hook, certificate expiry
- Short-lived public HTTPS certificates or ACME client troubleshooting

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves issue, challenge, renewal, renewal hook, or certificate lifecycle facts
  REFERENCE "references/acme-certbot.md"
CACHE loaded reference summaries for the rest of this task
```

Load only the relevant reference; do not preload the entire skill set.

## Workflow

1. Confirm certificate names, validation method, renewal owner, consumers, and the service's actual certificate paths.
2. Prefer the platform's signed package for Certbot; test issuance against the ACME staging directory before production use.
3. Use HTTP-01 only when the challenge endpoint is reachable; use DNS-01 with narrowly scoped credentials for wildcard or non-public endpoints.
4. Keep private keys out of repositories, tickets, logs, images, and chat; use workload identity or a managed credential store.
5. Make deploy hooks idempotent, install certificate and key with restrictive ownership/modes, validate service configuration, then reload only the affected service.
6. Run the renewal dry run and verify the served chain, SANs, and expiry; alert on both low remaining lifetime and failed renewal.

## Safety

- Never use a piped installer. If a package channel cannot provide the required client, use a dedicated environment with pinned, compatible client and plugin versions.
- Avoid broad DNS permissions and long-lived credential files; prefer short-lived identity federation or the host's workload identity.
- Coordinate revocation and replacement with consumers before rotating a certificate used for client authentication.

## Related skills

- SIP-TLS certificate deployment and client-auth requirements → `sec-sip-tls-manage`
- Key generation, certificate chains, and CA operations → `sec-tls-pki-manage`
- Web-server TLS policy review → `sec-tls-config-audit`
- DNS perimeter changes → `sec-network-perimeter-manage`
