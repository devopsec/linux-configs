# Kubernetes workload operations

Confirm kube context, cluster, namespace, and ownership before every task. `kubectl get`, `describe`, `events`, and bounded `logs` are the safe starting point; logs and descriptions may contain customer data or credentials and must be redacted.

## Read-only diagnosis

```bash
kubectl config get-contexts
kubectl config current-context
kubectl get deploy,statefulset,daemonset,job,cronjob,pod,svc,endpointslices -n "$NS" -o wide
kubectl get events -n "$NS" --sort-by=.lastTimestamp | tail -30
kubectl get events -A --field-selector type=Warning
kubectl describe pod "$POD" -n "$NS"
kubectl logs "$POD" -n "$NS" -c "$CONTAINER" --tail=100 --since=15m
kubectl logs deploy/"$DEPLOYMENT" -n "$NS" --all-containers --since=15m
kubectl top pods -n "$NS" --containers
kubectl auth can-i --list -n "$NS"
```

The bundled `scripts/k8s-diagnose.sh` performs read-only collection. Review its output before sharing; it can include events, image names, command arguments, and bounded application log lines.

## Workload selection and reliability

| Need | Kind | Considerations |
|---|---|---|
| Stateless service | Deployment | RollingUpdate, readiness/startup probes, PDB, HPA. |
| Stable identity or persistent volume | StatefulSet | Ordered rollout and volume recovery; prefer managed databases when appropriate. |
| Per-node agent | DaemonSet | Requires scheduling/toleration review and may not fit Autopilot. |
| Finite task | Job | Set retry limits, deadline, and cleanup policy. |
| Scheduled task | CronJob | Use `Forbid` concurrency when overlapping work is unsafe. |

Always set CPU/memory requests. Use startup probes for slow boot, readiness probes for traffic gating, and liveness probes only for a stuck process—not to restart on a downstream outage. Keep termination grace longer than application drain time. Use immutable image digests and per-workload service accounts.

## Configuration and secrets

Use ConfigMaps for non-secret configuration. Supply secret values via Secret Manager/External Secrets/CSI at deployment time; do not commit rendered Secret YAML or print Secret data. Inspect key names without values when diagnosing:

```bash
kubectl get secret "$SECRET" -n "$NS" -o jsonpath='{.data}' | jq 'keys'
```

## Rollout and recovery

```bash
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NS" --timeout=5m
kubectl rollout history deployment/"$DEPLOYMENT" -n "$NS"
kubectl diff -f "$MANIFEST"
```

`kubectl apply`, image updates, restart, rollback, deletion, node drain, ephemeral debug containers, and diagnostic pods mutate cluster state. Show the exact target, impact, and rollback path and get approval before running. If Helm or Kustomize owns the objects, use that tool or revert its source rather than direct `kubectl rollout undo`.

## Troubleshooting matrix

| State | First checks |
|---|---|
| `Pending` | Events, requests/limits, quota, taints, PVC binding, node capacity. |
| `ImagePullBackOff` | Image path/digest, workload identity or registry-reader role, pull policy. |
| `CrashLoopBackOff` | Bounded previous-container logs, exit code, config/secret references, probes. |
| `OOMKilled` | Last state, memory request/limit, recent load and leak signals. |
| Running but not Ready | Readiness path/port, selectors, endpoint slices, dependency reachability. |
| Evicted | Node pressure and ephemeral-storage requests. |
| Terminating indefinitely | Finalizers, storage, controller ownership; do not remove finalizers without impact review. |

## Scheduling and quotas

Use namespace `ResourceQuota` and `LimitRange` to bound teams and prevent unscheduled workloads. Choose values from measured service needs, not from generic sample quotas. Verify `metrics-server` before relying on `kubectl top`.

## References

- Kubernetes [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/), and [resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) — checked 2026-10-28.