# ACME with Certbot

## Contents

- Client version and lifecycle
- HTTP-01 and DNS-01
- Renewal and deploy hooks
- Verification and troubleshooting

## Client version and lifecycle

Certbot upstream release checked 2026-10-28: **5.8.0**. Distribution packages may lag; prefer the signed distribution package unless a specific client feature requires another channel. When using a non-distro client or plugin, pin compatible versions and verify their provenance before deployment.

Public ACME certificates are for server authentication. Confirm the issuer's current profile and intended use; do not depend on a public server certificate for client-auth EKU. Set monitoring based on the actual certificate lifetime and alert on renewal failures.

## HTTP-01

Use HTTP-01 only when the challenge path is reachable on the authorized endpoint. Test against the ACME staging directory first:

```bash
certbot certonly --staging --webroot -w <webroot> \
  -d <fqdn> --non-interactive --agree-tos -m "${ACME_EMAIL}"
```

For production, remove `--staging` only after the staging issuance succeeds and the contact address is approved. `--standalone` is appropriate only when no other service owns the challenge port.

## DNS-01

For wildcard names or endpoints that cannot receive HTTP validation, use a provider plugin with a workload identity that can modify only the required zone. On Google Cloud, use Application Default Credentials where available; avoid service-account key files.

```bash
certbot certonly --dns-google \
  --dns-google-propagation-seconds <seconds> \
  -d <fqdn> -d "*.<delegated-zone>" \
  --non-interactive --agree-tos -m "${ACME_EMAIL}"
```

Off-cloud credentials, if unavoidable, must be kept outside the repository with restrictive permissions and rotated. Use the provider's matching plugin and provider-documented credential format.

## Renewal and deploy hooks

Use the package's existing renewal timer rather than creating a second scheduler. Confirm timer state and perform a staging dry run before relying on unattended renewal:

```bash
systemctl list-timers --all | grep -i certbot
certbot renew --dry-run
certbot certificates
```

Deploy hooks should run only after successful renewal, handle only the intended certificate lineage, install key/certificate files with restrictive ownership and permissions, validate the consumer configuration, and reload the consumer only after validation. Keep each consumer's hook separate and review it with the repository's Bash rules.

```bash
#!/usr/bin/env bash
set -euo pipefail

nginx -t && systemctl reload nginx
```

Do not copy a private key into logs or print it from a hook. Use the consumer-specific certificate layout documented in `sec-sip-tls-manage` when the consumer is a SIP service.

## Verification and troubleshooting

| Symptom | Likely cause | Response |
|---|---|---|
| HTTP challenge times out | Challenge path is not reachable | Confirm DNS and the approved ingress path, or use DNS-01 |
| DNS challenge fails | Propagation or zone permissions | Confirm authoritative zone and narrowly scoped identity access |
| Renewal succeeds but service presents old certificate | Hook missing, skipped, or reload failed | Inspect renewal/service logs, validate config, then verify the served chain |
| Peer authentication breaks after renewal | Certificate purpose or trust changed | Check EKU, issuer chain, SAN, and peer trust; use a private/contracted CA for client authentication |

Never solve a renewal failure by disabling certificate validation or broadly granting DNS write access.