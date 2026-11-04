---
name: sec-sip-tls-manage
description: "Configure and operate TLS for SIP services, including Kamailio SIP-TLS, WSS termination, peer trust, and outbound mutual TLS. Use when a task mentions SIP-TLS, SIPS, Kamailio TLS, WSS, client certificates, carrier trust, or TLS reloads on a SIP edge."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/ssl-tls-management
  license: MIT
---

# SIP TLS management

Handle certificate placement, peer verification, and reload/validation for SIP TLS. Keep SIP routing and module configuration details aligned with the owning platform skill.

## Triggers

- SIP-TLS, SIPS, Kamailio TLS, WSS, mTLS, carrier certificate, TLS reload
- A SIP handshake, certificate chain, or peer-authentication failure

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves SIP certificate layout, peer trust, client authentication, reload, or verification
  REFERENCE "references/sip-tls.md"
  REFERENCE skill "dev-kamailio-platform-manage" AT "references/tls-and-transport.md" when Kamailio is used
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Identify whether the endpoint is a SIP server, a client authenticating to a peer, or both; confirm peers and expected names.
2. Select a public server certificate or a private/contracted CA certificate that supports the required EKU; do not use a public server-only certificate for client authentication.
3. Use only project-supplied paths and peer parameters. Protect keys with the service's least-readable ownership and restrictive mode.
4. Validate the chain, SAN, EKU, supported protocol, and peer identity before deployment; check the SIP application's config before reload.
5. Reload through the application-supported mechanism, verify new handshakes, and record any existing connections that continue to use prior sessions.

## Safety

- Never copy private keys into the repository, tickets, logs, or chat.
- Do not weaken certificate verification or enable obsolete protocol versions to work around a peer failure; document a scoped exception and obtain approval instead.
- Coordinate replacement and revocation with both sides of an mTLS connection.

## Related skills

- Public ACME issuance and renewal → `sec-tls-acme-manage`
- Private PKI and certificate-chain operations → `sec-tls-pki-manage`
- TLS server configuration review → `sec-tls-config-audit`
- SIP routing/module semantics → `dev-kamailio-platform-manage`
