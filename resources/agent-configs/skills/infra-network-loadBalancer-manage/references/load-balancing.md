# Google Cloud load-balancer selection and operation

## Defaults and configurable choice

Default to the simplest product that meets protocol and exposure requirements:

| Traffic | Default GCP class | Key constraint |
|---|---|---|
| Public HTTP(S), APIs, WebSockets | Global external Application Load Balancer | Layer 7; use only for HTTP(S) application traffic |
| Private HTTP(S) between services | Internal Application Load Balancer | Private frontend and backend reachability |
| SIP UDP/TCP/TLS ingress | Regional external passthrough Network Load Balancer | Layer 4; preserves client traffic behavior required by SIP |
| Private TCP/UDP between tiers | Internal passthrough Network Load Balancer | Private VIP; verify protocol support and region |

Defaults may be overridden by `~/.junie/custom/configs/infra/load-balancer.toml` using the `http_class` and `sip_signaling_class` keys shown in `assets/config.example.toml`. Ask for protocol, exposure, location, backend type, client-IP need, and HA design when unclear. Product/API names can change; check the project's supported GCP API and installed CLI help before proposing a new resource.

## Inspect before change

```bash
gcloud compute forwarding-rules list
gcloud compute backend-services list
gcloud compute backend-services get-health <backend-service> --region=<region>
```

Inspect frontend address/scope, IP protocol/ports, backend membership, health-check configuration, firewall policy, session affinity, connection draining, logging, and IaC ownership. Preserve all existing rules not in the approved change.

## HTTP(S) backends

Use an Application Load Balancer for HTTP(S) features such as host/path routing, managed certificates, Cloud Armor, and Cloud CDN. Define a health endpoint that reflects application readiness but does not expose sensitive diagnostics. Restrict backend access to the load balancer and probe paths required by the selected product.

Trust `X-Forwarded-For` only when the backend can identify the actual load-balancer hop and discard spoofable client-supplied values. Use Cloud Armor controls and logging appropriate to the data and exposure.

## SIP signaling and media

For SIP UDP/TCP/TLS, use a passthrough L4 product where its protocol/region/backend constraints fit. A GCP load balancer is an ingress VIP, not a SIP-aware proxy: use Kamailio dispatcher for call-aware distribution and ensure signaling headers advertise the reachable VIP as intended. A health check must reflect routing readiness, not simply that a TCP socket is open.

Do not load-balance RTP as HTTP. Media endpoints and RTP port ranges must come from the service owner; ask for approved ranges, public/private addresses, and carrier/client source scope. Check firewall rules and conntrack policy with the perimeter owner.

## Health, rollout, and draining

Allow only documented probe sources to the configured health-check ports. Never copy source ranges from an old skill or guess runtime ports; consult current provider docs and the project's firewall policy.

1. Verify all intended backends are healthy before cutover.
2. Add or modify the frontend/backend through IaC where it owns the resource; review the plan.
3. Drain a backend before maintenance and account for in-flight requests/calls.
4. Validate externally and from the private network; inspect provider health and application logs.
5. Keep a rollback plan for forwarding rules, backend membership, and DNS changes.

## Troubleshooting

| Symptom | Check |
|---|---|
| All backends unhealthy | health-check protocol/path/port, firewall, readiness response |
| HTTP 502/503 | backend protocol/port, TLS mode, logs, endpoint health |
| SIP one-way signaling | backend source/destination behavior, advertised address, firewall, packet capture |
| Large SIP message loss | selected L4 protocol handling and fragmentation behavior |
| Uneven node distribution | session affinity, client NAT concentration, SIP dispatcher health |

HAProxy/nginx reverse-proxy configuration is out of scope; see `infra-nginx-reverseProxy-manage` for HTTP proxy behavior.