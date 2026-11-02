# SIP/RTP perimeter exposure

This reference defines perimeter flows only. Keep SIP application configuration in `dev-kamailio-platform-manage` and active verification in `sec-sip-securityTest-run`.

## Flow matrix

| Flow | Protocol/port | Source rule |
|---|---|---|
| SIP signalling | UDP/TCP 5060 | Approved peer/customer CIDRs only where possible |
| SIP over TLS | TCP 5061 | Approved peer CIDRs; certificate policy is separate |
| SIP over DTLS | UDP 5061 | Enable only if configured and approved |
| SIP over WSS | TCP configured HTTPS listener | Browsers or trusted proxy/LB path |
| RTP/RTCP | UDP configured media range | Use exact deployed `port-min`/`port-max`; do not guess |
| RPC/control, admin UI | Local/private management only | Never expose publicly |
| Database | Private application path only | Do not open to internet sources |

Treat source CIDRs, listener overrides, and RTP bounds as runtime inputs from the service config or user. A range used in one environment is not a default for another.

## SIP helper and NAT

SIP conntrack helpers can rewrite SDP and break calls. Check whether the helper is loaded or explicitly assigned before disabling it; validate existing host dependencies and apply persistent changes through the platform's source configuration.

Cloud 1:1 NAT may require the application/media service to advertise an external address while binding to a private interface. Obtain the external/private addresses from approved runtime configuration, and verify both signalling and media paths. Never infer public addresses.

## Layered controls

1. Restrict cloud ingress to approved peer sources where operationally possible.
2. Enforce the same flow intent in one host firewall manager; keep media ranges aligned with the running media service.
3. Apply application-level rate limiting and monitoring for SIP signaling; avoid broad allow rules.
4. Keep RPC, control, database, and administrative interfaces on local or private management paths.
5. Validate a controlled test call and the approved allow/deny paths; do not use floods or broad network scans.