# KServe model serving

KServe `v0.21.0` checked 2026-10-28. Pin CRDs and controller charts to the same version; confirm Kubernetes compatibility and deployment mode before upgrading. This reference is KServe-specific; generic Kubernetes policy and standalone Triton operations belong to their own skills.

## Install mode

Choose `RawDeployment` when the cluster does not run Knative; choose Serverless only when the Knative serving stack is installed and operated. Review the versioned chart/values and obtain approval before applying to a shared cluster:

```bash
helm install kserve-crd oci://ghcr.io/kserve/charts/kserve-crd \
    --version v0.21.0 --namespace kserve --create-namespace &&
helm install kserve oci://ghcr.io/kserve/charts/kserve \
    --version v0.21.0 --namespace kserve \
    --set kserve.controller.deploymentMode=RawDeployment &&
kubectl get crd inferenceservices.serving.kserve.io
```

Use the exact versioned chart source and review chart values/upgrade notes before applying changes to a shared cluster.

## InferenceService baseline

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: <service-name>
  namespace: <namespace>
spec:
  predictor:
    minReplicas: 1
    maxReplicas: 4
    model:
      modelFormat:
        name: huggingface
      storageUri: gs://<private-bucket>/models/<model>/<immutable-revision>
      args: ["--max-model-len=8192"]
      resources:
        requests: {nvidia.com/gpu: "1", cpu: "4", memory: 20Gi}
        limits: {nvidia.com/gpu: "1", memory: 24Gi}
```

Use a workload identity with read-only access to the model artifact, a private namespace/network path, explicit requests/limits, and readiness/startup behavior appropriate for long model loads. Mirror trusted runtime images into an approved registry and pin their digests.

## Canary, promotion, rollback

Canary traffic splitting through KServe requires Serverless/Knative mode. In `RawDeployment`, implement weighted routing at the LLM gateway instead. For Serverless, prepare a candidate manifest with the new model URI and `canaryTrafficPercent: 20`, review the diff, then apply it:

```bash
kubectl apply -f '<candidate-manifest.yaml>'
```

After per-revision readiness, p95 latency, errors, and evaluation score pass, an approved operator may adjust the split:

```bash
kubectl patch isvc '<service-name>' -n '<namespace>' --type=json \
    -p='[{"op":"replace","path":"/spec/predictor/canaryTrafficPercent","value":50}]'
```

Only after the candidate passes and the user approves promotion, remove the canary field:

```bash
kubectl patch isvc '<service-name>' -n '<namespace>' --type=json \
    -p='[{"op":"remove","path":"/spec/predictor/canaryTrafficPercent"}]'
```

To roll back, return traffic to the stable revision and restore its recorded model URI:

```bash
kubectl patch isvc '<service-name>' -n '<namespace>' --type=json \
    -p='[{"op":"replace","path":"/spec/predictor/canaryTrafficPercent","value":0}]'
```

Inspect service state separately:

```bash
kubectl get isvc -n '<namespace>' -w
```

Inspect details from another terminal:

```bash
kubectl describe isvc '<service-name>' -n '<namespace>' &&
kubectl logs -n '<namespace>' 'deploy/<predictor-deployment>' --tail=200
```

Traffic changes affect production routing; require explicit approval and keep the previous model URI recorded.

## Common failure checks

| Symptom | First checks |
|---|---|
| Predictor pending | GPU quota, node selector/taint, resource requests, and autoscaler ceiling. |
| Service not ready | Storage permissions, model URI/revision, storage initializer logs, startup probe. |
| Memory failure | Model size/precision, `/dev/shm`, limits, and GPU memory. |
| Canary does not route | Serverless mode and Knative readiness; otherwise use gateway weights. |

Do not change public ingress, GPU replica bounds, or production route weights without explicit target and approval.