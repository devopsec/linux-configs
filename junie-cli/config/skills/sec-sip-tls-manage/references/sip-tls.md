# SIP TLS certificate operations

## Contents

- Certificate purpose and peer identity
- Key and trust-file layout
- Kamailio TLS profile shape
- Reload and verification

## Certificate purpose and peer identity

| Use | Certificate source | Required check |
|---|---|---|
| SIP server certificate | Public CA or contracted CA | SAN matches the peer's expected DNS name |
| Outbound client certificate | Private or contracted CA that issues client-auth certificates | EKU includes TLS client authentication |
| Trusting a carrier/client | Peer-provided or agreed CA chain | Verify issuer and trust scope before adding it |
| Internal SIP hop | Managed private CA | Limit trust to the intended service boundary |

Inspect a client certificate's EKU before deploying it:

```bash
openssl x509 -in <client-certificate> -noout -ext extendedKeyUsage
```

SIP routing and module parameter details belong to `dev-kamailio-platform-manage`; this reference covers certificate use, file permissions, reload, and peer validation.

## Key and trust-file layout

Use paths from the service's configuration of record. A typical layout separates server credentials, client credentials, and trusted peer CAs:

```text
<tls-directory>/
  <server-chain-file>       service-readable, not world-readable
  <server-key-file>         owner/service-group only
  <client-chain-file>       only when outbound mTLS is required
  <client-key-file>         owner/service-group only
  <peer-ca-bundle>          public certificates only
```

Keep deployed copies independent of an ACME client's private archive directory when the consumer cannot traverse that directory. On SELinux hosts, apply a persistent file-context rule and restore labels after deployment; do not disable SELinux to make certificate access work.

## Kamailio TLS profile shape

The following is a shape, not a complete configuration. Confirm parameter names against the installed Kamailio version and local module documentation:

```ini
[server:default]
method = TLSv1.2+
certificate = <server-chain-path>
private_key = <server-key-path>
ca_list = <peer-ca-bundle>
verify_certificate = no
require_certificate = no

[client:default]
method = TLSv1.2+
verify_certificate = yes
ca_list = <system-or-approved-ca-bundle>
```

Enable client-certificate verification and `require_certificate` only for endpoints whose policy requires inbound mTLS. Configure per-peer client credentials and server-name verification where supported; do not disable verification as a generic workaround.

## Reload and verification

Use the application's supported reload mechanism after checking configuration syntax. For Kamailio, a TLS module reload can apply certificate changes without a full restart; confirm behavior for the installed build and inspect logs if reload fails. Existing sessions may continue under the certificate negotiated at connection setup.

```bash
kamcmd tls.reload
kamcmd tls.info
openssl s_client -connect <sip-fqdn>:<sip-tls-port> \
  -servername <sip-fqdn> -verify_return_error </dev/null
```

For outbound mTLS, test with an approved peer and the intended client certificate and CA bundle. Confirm SAN, chain, EKU, protocol, and SIP-level health. Coordinate certificate replacement with the peer before revoking the old certificate.