---
name: infra-serviceMesh-any-manage
description: "Compare and operate Istio or Linkerd service meshes on Kubernetes, including mTLS, authorization, traffic routing, sidecar/ambient injection, and mesh upgrades. Use when requests mention service mesh, Istio, Linkerd, PeerAuthentication, VirtualService, Gateway API HTTPRoute, or mesh mTLS."
metadata:
  source: https://github.com/BagelHole/DevOps-Security-Agent-Skills
  upstream:
    - infrastructure/networking/service-mesh
  license: MIT
---

# Kubernetes service mesh manage

Do not introduce a mesh without a concrete mTLS, L7 policy, or cross-cluster requirement; it adds a control plane, data plane, and upgrade surface.

## Triggers

- Istio, Linkerd, Cloud Service Mesh, sidecar/ambient, mesh injection
- mTLS, `PeerAuthentication`, `AuthorizationPolicy`, `VirtualService`, Gateway API `HTTPRoute`

## Load order (SAD KITTI)

```sadkitti
REQUIRE project AGENTS.md or Kubernetes README if present
IF file exists "~/.junie/custom/configs/infra/serviceMesh.toml"
  REFERENCE "~/.junie/custom/configs/infra/serviceMesh.toml"
ELSE
  use Istio 1.31.3 for richer L7 policy/traffic controls; use Linkerd edge-26.10.1 for a smaller simpler mesh only when edge channel is accepted
IF task involves mesh design, installation, policy, routing, or upgrades
  REFERENCE "references/service-mesh.md"
IF workload behavior or rollout validation is needed
  REFERENCE skill "infra-kubernetes-workload-manage"
IF cluster security baseline or certificate issuer is involved
  REFERENCE skill "sec-kubernetes-cluster-harden"
CACHE Kubernetes version, mesh, exact mesh version, namespace, trust model, and change window
```

## Workflow

1. Confirm the concrete requirement, cluster version, CNI, Gateway API version, existing ingress, and workload compatibility.
2. Read the config if present; explain any override and prefer one mesh per cluster unless a migration plan requires coexistence.
3. Pin mesh/Helm versions, trust anchor, CRD versions, and control-plane revision; keep trust material out of the repository.
4. Pilot in a non-production namespace, observe traffic, and test mTLS/auth policy before enforcing strict mode broadly.
5. Enable injection for selected namespaces/workloads and use canary control-plane upgrades.
6. Verify proxy/ambient status, mTLS, authorization, service reachability, and rollback path.

## Related skills

- `infra-gcp-gke-manage` — GKE cluster and Cloud Service Mesh context.
- `infra-helm-chart-manage` — versioned chart operations.
- `infra-kubernetes-workload-manage` — workload injection and rollout.
- `sec-kubernetes-cluster-harden` — certificate issuers and cluster security.
