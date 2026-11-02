---
name: sec-tls-config-audit
description: "Audit TLS endpoints and web-server configuration for certificate validity, chain delivery, protocol versions, cipher policy, and expiry monitoring. Use when a task mentions TLS configuration review, OpenSSL probing, nginx or Apache TLS, cipher suites, certificate expiry checks, or HTTPS hardening."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/ssl-tls-management
  license: MIT
---

# TLS configuration audit

Assess TLS configuration and endpoint behavior using non-destructive checks first; make any active probe or configuration change only on authorized targets.

## Triggers

- TLS configuration audit, HTTPS hardening, nginx/Apache TLS, cipher policy
- OpenSSL endpoint checks, certificate expiry monitoring, protocol negotiation failures

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF file "~/.junie/custom/configs/security/tls.toml" exists
  REFERENCE "~/.junie/custom/configs/security/tls.toml"
ELSE
  use defaults: OpenSSL for endpoint inspection; the installed server's native config-test command for local syntax validation
IF task involves protocol/cipher policy, web-server config, or expiry monitoring
  REFERENCE "references/tls-config-audit.md"
CACHE loaded reference summaries for the rest of this task
```

Load only the selected reference and settings relevant to the target.

## Workflow

1. Confirm authorized endpoints, names, ports, maintenance windows, TLS policy, and source of truth for configuration.
2. Inspect certificate dates, SANs, chain, negotiated protocol, and service configuration before proposing a change.
3. Compare against a modern policy that supports TLS 1.2 and TLS 1.3; identify compatibility exceptions rather than weakening the baseline.
4. Validate configuration with the service's native test command and probe the exact SNI name after deployment.
5. Monitor expiry and renewal failures; record evidence and rollback steps without storing private keys.

## Safety

- Use the configured probe tool only against authorized targets; do not scan arbitrary networks.
- Avoid TLS downgrade flags except in a controlled negative test that confirms legacy protocols are rejected.
- Keep endpoint names and network ranges as runtime inputs; do not infer site targets.

## Related skills

- ACME certificate lifecycle → `sec-tls-acme-manage`
- PKI, key and chain operations → `sec-tls-pki-manage`
- SIP TLS configuration → `sec-sip-tls-manage`
