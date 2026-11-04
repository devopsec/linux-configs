# TLS endpoint and server-configuration audit

## Contents

- Endpoint inspection
- Web-server baseline
- Protocol policy
- Expiry monitoring

## Endpoint inspection

Run checks only against authorized endpoints and use the intended SNI name:

```bash
openssl s_client -connect <host>:<port> -servername <dns-name> \
  -showcerts -verify_return_error </dev/null
openssl s_client -connect <host>:<port> -servername <dns-name> </dev/null \
  2>/dev/null | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Check chain completeness, SAN, validity, negotiated protocol, and whether invalid/untrusted chains fail closed. Use a controlled test to confirm deprecated protocol versions are rejected rather than probing unapproved address ranges.

## Web-server baseline

For nginx, the policy shape should restrict protocols, use a maintained cipher policy, avoid session-ticket key reuse without rotation, and serve the full chain:

```nginx
server {
    listen 443 ssl;
    server_name <fqdn>;
    ssl_certificate <full-chain-path>;
    ssl_certificate_key <private-key-path>;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_tickets off;
}
```

For Apache, apply the equivalent TLS 1.2/1.3 policy using syntax supported by the installed release and validate with its native configuration test. On RHEL-family systems, prefer the maintained system crypto policy unless a documented application requirement justifies a scoped override.

Do not enable HTTP Strict Transport Security preload until every affected subdomain is HTTPS-capable and the owner accepts the difficult reversal process. Do not add obsolete OCSP stapling directives for an issuer that no longer supports OCSP.

## Protocol policy

Use TLS 1.2 and TLS 1.3 with modern AEAD cipher suites and ephemeral key exchange, subject to a documented compatibility matrix. Avoid TLS 1.0/1.1 and weak key exchange. For application runtimes, use the platform's verified default trust context and enforce the minimum protocol version; never disable certificate verification to work around a failed handshake.

## Expiry monitoring

Monitor each authorized endpoint using its configured host, port, and SNI values from approved TOML/runtime settings. Alert before the renewal window and immediately on failed checks. Cloud Monitoring uptime checks can cover supported HTTPS endpoints; use an approved scheduled probe for other protocols and protect its logs from leaking target or certificate details.

Record the observed issuer, expiry, SAN, and probe time. The maintenance owner should confirm actual configured renewal timers and that the served certificate changes after renewal.