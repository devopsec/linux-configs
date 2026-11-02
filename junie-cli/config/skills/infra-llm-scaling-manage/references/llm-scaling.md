# KEDA-based LLM scaling

KEDA `v2.21.0` checked 2026-10-28. Pin the Helm chart/operator version and review its upgrade notes before changing a cluster.

## Select safe scaling signals

GPU utilization alone is a poor signal for vLLM because memory may be preallocated. Prefer queue depth, KV-cache pressure, throughput, or an SLO signal, and validate metric names from the deployed vLLM `/metrics` endpoint.

| Signal | Example | Use |
|---|---|---|
| Waiting requests | `vllm:num_requests_waiting` | Scale before queue delay violates the SLO. |
| KV cache | `vllm:kv_cache_usage_perc` | Scale or shed load as cache pressure rises. |
| TTFT | `vllm:time_to_first_token_seconds` | SLO guardrail; pair with queue depth. |
| Queue length | Pub/Sub subscription backlog | Scale batch workers; permit zero only for durable jobs. |

## Online inference: ScaledObject

Keep at least one warm replica for interactive inference unless the user explicitly accepts cold-start delay. The values below are a test example, not a production capacity recommendation.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: <deployment-name>
  namespace: <namespace>
spec:
  scaleTargetRef:
    name: <deployment-name>
  minReplicaCount: 1
  maxReplicaCount: 4
  cooldownPeriod: 300
  pollingInterval: 15
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://<prometheus-service>:9090
        query: sum(vllm:num_requests_waiting{model_name="<served-model>"})
        threshold: "10"
    - type: prometheus
      metadata:
        serverAddress: http://<prometheus-service>:9090
        query: avg(vllm:kv_cache_usage_perc{model_name="<served-model>"})
        threshold: "0.8"
```

Set `maxReplicaCount` from GPU quota, serving capacity, and a confirmed cost ceiling. Use KEDA `TriggerAuthentication`/workload identity for authenticated monitoring endpoints; do not place credentials in trigger metadata.

## Batch queue: ScaledJob

Use a durable queue and idempotent worker. On GCP, KEDA's Pub/Sub scaler can authenticate with workload identity:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: <batch-job>
  namespace: <namespace>
spec:
  jobTargetRef:
    template:
      spec:
        serviceAccountName: <worker-service-account>
        restartPolicy: OnFailure
        containers:
          - name: worker
            image: <region>-docker.pkg.dev/<project>/<repo>/<worker>:<version>
  minReplicaCount: 0
  maxReplicaCount: 20
  pollingInterval: 10
  triggers:
    - type: gcp-pubsub
      authenticationRef:
        name: <pubsub-workload-identity-auth>
      metadata:
        subscriptionName: <subscription>
        mode: SubscriptionSize
        value: "5"
```

Ack only after durable output is written; configure bounded retries, dead-letter handling, and idempotency keys so worker restarts do not duplicate work.

## GPU capacity and validation

- Keep an on-demand baseline; use spot GPUs for burst only with graceful termination, checkpoint/retry, and an on-demand fallback.
- Check regional GPU quota and cluster autoscaler limits before raising replica ceilings. Model/node startup includes provisioning, image pull, and weight load.
- Test scale-out, scale-in, queue replay, spot interruption, metric outage, and quota exhaustion. Confirm SLO and estimated cost at the maximum.
- KEDA scales workloads, not GPU node pools. Use the managed cluster autoscaler or the applicable cloud infrastructure skill for node capacity.