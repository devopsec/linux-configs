# TLS PKI practices

## Contents

- Key generation and CSR
- Certificate inspection and validation
- Trust and lifecycle controls

## Key generation and CSR

Choose key type and size according to the current organizational cryptographic policy and all required client capabilities. Generate private keys locally, set restrictive permissions immediately, and send only the CSR to the authorized issuer.

```bash
umask 077
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out <private-key>
chmod 0600 <private-key>

openssl req -new -key <private-key> -out <request.csr> \
  -subj "/CN=<fqdn>" \
  -addext "subjectAltName=DNS:<fqdn>,DNS:<alternate-fqdn>"
```

Do not place real identities in examples or commit a private key. A self-signed certificate is for isolated development/testing only; it is not a substitute for a trusted production issuer.

## Certificate inspection and validation

```bash
openssl x509 -in <certificate> -noout -subject -issuer -dates \
  -ext subjectAltName,extendedKeyUsage
openssl verify -CAfile <trusted-chain> <certificate>
openssl x509 -in <certificate> -noout -checkend <seconds>
```

Verify the issued certificate against the request and intended use: SAN, EKU, key algorithm, validity, issuer, chain order, and trust path. To compare public keys without displaying the private key:

```bash
diff \
  <(openssl x509 -in <certificate> -noout -pubkey) \
  <(openssl pkey -in <private-key> -pubout)
```

For encrypted PKCS#12 output, read passphrases from a protected environment variable or credential manager, never command history. If extracting an unencrypted key, restrict its mode and securely remove it after the intended operation.

## Trust and lifecycle controls

- Keep signing keys in the CA's managed HSM/control plane; separate certificate issuance from trust-anchor changes.
- Scope trust bundles to the intended peer or service boundary and remove obsolete issuers through a reviewed change.
- Monitor expiry against actual validity duration and renewal lead time; document the responsible owner and failure alert.
- Before revocation, identify relying parties and replacement-chain readiness; preserve audit records for issuance and revocation.
- Treat private key compromise as a security incident, not merely a renewal task.