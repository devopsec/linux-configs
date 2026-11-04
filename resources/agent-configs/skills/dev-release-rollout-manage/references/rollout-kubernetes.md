# Rollout & rollback on Kubernetes

kubectl/Helm mechanics → `infra-kubernetes-any-manage`. Always deploy by image **digest** taken from the verified release.

## Strategy choice

| Strategy | Mechanism | Rollback speed | Cost |
|---|---|---|---|
| Rolling (default) | Deployment `RollingUpdate maxSurge 1 / maxUnavailable 0` | minutes (`rollout undo`/`helm rollback`) | none |
| Blue-green | two Deployments, Service selector switch | seconds (selector back) | 2× capacity during switch |
| Canary (replica ratio) | stable + canary Deployments behind one Service | fast (scale canary 0) | coarse % (by replicas) |
| Canary (weighted) | Istio/Gateway API weights or Argo Rollouts / Flagger | fast, automated analysis | mesh/controller |

## Rolling

```bash
kubectl set image deploy/myapp myapp="${IMG}@sha256:${DIGEST}" -n "$NS"
kubectl annotate deploy/myapp kubernetes.io/change-cause="vX.Y.Z" -n "$NS" --overwrite
kubectl rollout status deploy/myapp -n "$NS" --timeout=10m
# rollback
kubectl rollout undo deploy/myapp -n "$NS"            # or helm rollback rel <rev> / git revert overlay
```

Readiness probe + `preStop` sleep + PDB make rolling zero-downtime. `progressDeadlineSeconds` fails stuck rollouts.

## Blue-green (Service selector switch)

```yaml
# Two Deployments: myapp-blue (version: blue) and myapp-green (version: green)
apiVersion: v1
kind: Service
metadata: { name: myapp }
spec:
  selector: { app: myapp, version: blue }   # live colour
  ports: [{ port: 80, targetPort: http }]
```

```bash
kubectl rollout status deploy/myapp-green -n "$NS"
kubectl port-forward deploy/myapp-green 8080:8080 -n "$NS"   # smoke test, then:
kubectl patch svc myapp -n "$NS" --type=merge -p '{"spec":{"selector":{"app":"myapp","version":"green"}}}'
# rollback: patch selector back to blue (keep blue scaled up for the rollback window)
```

Keep the switch in git (Kustomize overlay / Helm value `activeColor`) so the cluster matches source. Health-check via `kubectl exec` is unreliable in distroless images — probe through a Service or port-forward.

## Canary with weights (Istio / Gateway API)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: myapp }
spec:
  parentRefs: [{ name: app-gateway }]
  rules:
    - backendRefs:
        - { name: myapp-stable, port: 80, weight: 90 }
        - { name: myapp-canary, port: 80, weight: 10 }
```

Step weights 5 → 25 → 50 → 100 with bake time and SLO checks between; abort = weight 0 for canary. Istio `VirtualService` equivalent in `infra-kubernetes-any-manage/references/service-mesh.md`.

## Argo Rollouts (automated canary + analysis)

Install the organization-approved release via its Helm chart or reviewed manifest; pin the manifest and plugin to an exact version and verify the published checksum/signature before use.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: myapp }
spec:
  replicas: 5
  revisionHistoryLimit: 5
  selector: { matchLabels: { app: myapp } }
  template: { }                      # same pod template as the Deployment
  strategy:
    canary:
      canaryService: myapp-canary
      stableService: myapp-stable
      trafficRouting:
        istio: { virtualService: { name: myapp } }   # or a Gateway API traffic-router plugin
      steps:
        - setWeight: 10
        - pause: { duration: 10m }
        - analysis: { templates: [{ templateName: error-rate }] }
        - setWeight: 50
        - pause: { duration: 10m }
---
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata: { name: error-rate }
spec:
  metrics:
    - name: error-rate
      interval: 2m
      failureLimit: 1
      successCondition: result[0] < <APPROVED_ERROR_RATE_THRESHOLD>
      provider:
        prometheus:
          address: ${PROMETHEUS_URL}
          query: |
            sum(rate(http_requests_total{app="myapp",code=~"5.."}[5m]))
            / sum(rate(http_requests_total{app="myapp"}[5m]))
```

On GKE with Managed Service for Prometheus use its query frontend address. Commands: `kubectl argo rollouts get rollout myapp -w`, `promote`, `abort`, `undo`.

## Rollback checklist

1. Confirm the trigger (threshold breached, not noise) and announce in the incident/release channel.
2. Roll back with the tool that owns the object (Helm/Argo/GitOps), not ad-hoc `kubectl edit`.
3. Verify: pods on previous digest (`kubectl get pods -o jsonpath='{..image}'`), error rate back to baseline.
4. Data: confirm schema still compatible with the previous version (expand/contract migrations).
5. Record: what failed, timeline, follow-up; next release is a new patch, never a moved tag.
