---
name: sec-tls-pki-manage
description: "Manage TLS public-key infrastructure tasks such as key and CSR generation, certificate inspection, chain validation, CA trust, and renewal or revocation planning. Use when a task mentions OpenSSL, PKI, CSR, SAN, EKU, certificate chain, private CA, or certificate revocation."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - security/network/ssl-tls-management
  license: MIT
---

# TLS PKI management

Guide key, CSR, certificate-chain, trust, and revocation operations without coupling the workflow to a particular CA vendor.

## Triggers

- OpenSSL, PKI, key pair, CSR, SAN, EKU, certificate chain, trust store
- Private CA issuance, certificate validation, renewal, or revocation planning

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or platform README if present
IF task involves key generation, CSR, certificate inspection, chain validation, or PKI lifecycle
  REFERENCE "references/pki-practices.md"
CACHE loaded reference summaries for the rest of this task
```

## Workflow

1. Establish identity, intended use, required SANs/EKUs, key algorithm, lifetime, issuer, and trust path before creating a key or request.
2. Generate private keys locally with restrictive permissions; submit only the CSR to the authorized issuer.
3. Verify issuer, dates, SAN, EKU, chain order, and key/certificate correspondence before deployment.
4. Confirm all clients trust the replacement chain; schedule renewal before expiry and document revocation dependencies.
5. Keep CA signing keys in managed HSM/CA controls, separate issuance from trust-anchor administration, and audit privileged actions.

## Safety

- Never transmit or commit private keys; redact passphrases and sensitive identity data.
- Prefer modern key algorithms and cryptographic policies supported by the full client population; do not silently preserve obsolete algorithms for convenience.
- Revoke only after impact and replacement trust have been assessed.

## Related skills

- ACME public certificate issuance → `sec-tls-acme-manage`
- SIP server and peer certificate operations → `sec-sip-tls-manage`
- TLS configuration audit → `sec-tls-config-audit`
