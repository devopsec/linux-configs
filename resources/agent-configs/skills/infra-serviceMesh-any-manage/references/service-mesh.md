# Istio and Linkerd

Choose one mesh only for an explicit requirement. Istio release `1.31.3` (2026-10-22), Linkerd edge `edge-26.10.1` (2026-10-05), and Helm `4.3.1` were checked on 2026-10-28. Linkerd’s edge channel is not a stable release channel; do not use it where that risk is unacceptable.

| | Istio `1.31.3` | Linkerd `edge-26.10.1` |
|---|---|---|
| Data plane | Envoy sidecar or ambient ztunnel/waypoint | Rust micro-proxy sidecar |
| Strength | Rich L7 policy, traffic shaping, Gateway API | Smaller footprint and simpler service-to-service mTLS |
| Operations | More control-plane components and configuration | Edge-channel cadence; plan versioned upgrades |

On GKE, Cloud Service Mesh is the managed Istio option. Keep managed mesh and self-managed Helm/CLI lifecycle separate; never install both control planes over the same workload without a migration design.

## Installation and versions

Pin the mesh charts and CLI to the same approved release. Helm `4.3.1` uses `--rollback-on-failure`; review CRDs separately.

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm upgrade --install istio-base istio/base -n istio-system --create-namespace \
  --version 1.31.3 --rollback-on-failure --wait
helm upgrade --install istiod istio/istiod -n istio-system \
  --version 1.31.3 --rollback-on-failure --wait
```

For ambient mode, add only the required CNI/ztunnel/waypoint components and validate cluster CNI and policy compatibility first.

Linkerd edge charts and CLI must use the exact release selected in configuration:

```bash
helm repo add linkerd-edge https://helm.linkerd.io/edge
helm upgrade --install linkerd-crds linkerd-edge/linkerd-crds -n linkerd \
  --create-namespace --version edge-26.10.1 --rollback-on-failure --wait
helm upgrade --install linkerd-control-plane linkerd-edge/linkerd-control-plane -n linkerd \
  --version edge-26.10.1 --rollback-on-failure --wait
```

Linkerd identity trust anchor and issuer keys must be provisioned from an approved secret manager into restricted ephemeral files; never commit the files or pass their content as visible values. Validate Gateway API CRDs and the mesh compatibility matrix before install.

## Workload enrollment and policy

Enable injection only for named namespaces/workloads; restart pods only after the change is approved. Use revision labels for Istio control-plane canaries. Begin with observed/permissive mTLS where supported, confirm all clients are enrolled, then enforce strict mTLS. Start authorization policies in audit/report mode where possible and block only after validating required traffic.

Use Gateway API `HTTPRoute` or mesh-native routing only for supported HTTP/gRPC traffic. Review retries, timeout, connection pool, outlier detection, and fault injection as application behavior changes—not only networking configuration.

## Protocol and workload boundaries

Mesh L7 policies are not a substitute for network firewalls. Non-HTTP UDP protocols and externally advertised media paths require protocol-specific validation; keep them outside L7 routing unless an explicit compatibility test proves otherwise. Project-specific protocol boundaries belong in a project reference.

## Diagnostics and upgrades

Use `istioctl analyze`, proxy status/config, and `linkerd check` to inspect only the target namespace. `linkerd viz tap` or equivalent live-traffic tools can expose sensitive payload metadata; use only when required and sanitize output. Upgrade one minor/revision at a time, verify CRD behavior, canary control plane, then move workload revisions; preserve a previous known-good control plane.

## References

- [Istio 1.31.3 release](https://github.com/istio/istio/releases/tag/1.31.3) — published 2026-10-22; checked 2026-10-28.
- [Linkerd edge-26.10.1 release](https://github.com/linkerd/linkerd2/releases/tag/edge-26.10.1) — checked 2026-10-28.
- [Helm v4.3.1 release](https://github.com/helm/helm/releases/tag/v4.3.1) — checked 2026-10-28.