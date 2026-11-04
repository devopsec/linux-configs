# TLS and transport

## Paths

- Cert/key/CA paths appear in cfg **and** install/configure scripts — update both.
- Prefer existing path layout (`/etc/...`, platform `certs/`).
- Modes: `TLS`, `WSS`, mutual TLS (request client cert).

## mTLS

- `verify_certificate`, `require_certificate`, client CA bundle.
- Ensure reload/restart story is documented; private keys stay mode `0600` root-owned as per project norms.

## Checklist when changing TLS

- [ ] cfg listen + tls module params
- [ ] install script path creation
- [ ] configure/reconfigure script
- [ ] systemd/unit or container mount
- [ ] docs / runbook
- [ ] no cert material pasted into chat or committed
