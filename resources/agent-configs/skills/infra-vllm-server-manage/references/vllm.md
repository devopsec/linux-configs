# vLLM private inference server

Version checked 2026-10-28: vLLM `v0.32.0`. Match the container/wheel to its supported CUDA and driver combination; mirror the image and pin its digest for repeatable deployment.

## Capacity and runtime inputs

Before deployment collect the model ID and immutable revision, GPU type/count, model precision, context length, expected concurrency, latency/throughput targets, and private endpoint boundary. Estimate weight memory plus KV-cache memory; benchmark on the intended hardware rather than assuming a GPU model will fit.

## Start a private server

```bash
SECRET_NAME='<secret-name>' &&
SECRET_VERSION='<approved-secret-version>' &&
PYTHON_VERSION='<approved-python-patch>' &&
MODEL_ID='<approved-model-id>' &&
MODEL_REVISION='<immutable-model-commit>' &&
MAX_MODEL_LEN='<context-limit>' &&
uv venv --python "$PYTHON_VERSION" &&
uv pip install 'vllm==0.32.0' &&
export VLLM_API_KEY="$(gcloud secrets versions access "$SECRET_VERSION" --secret="$SECRET_NAME")" &&
vllm serve "$MODEL_ID" \
    --revision "$MODEL_REVISION" \
    --host localhost --port 8000 \
    --api-key "${VLLM_API_KEY}" \
    --gpu-memory-utilization 0.90 \
    --max-model-len "$MAX_MODEL_LEN" \
    --enable-prefix-caching
```

In a second terminal, check readiness:

```bash
curl -fsS http://localhost:8000/health
```

For containers, use a digest-pinned `vllm/vllm-openai` image, read-only model mounts where practical, a dedicated runtime identity, and a private bind/network. Pre-stage weights and set offline mode after confirming the exact model revision is available locally. Never embed a model-hub token in a manifest or command history.

## Kubernetes / GKE deployment

Use Workload Identity for private GCS model artifacts, a GKE GPU node pool, a gateway-only `NetworkPolicy`, and a `PodDisruptionBudget`. Node-pool creation and GPU quota are owned by `infra-gcp-gke-manage`; this template is only the vLLM workload:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <deployment-name>
  namespace: <namespace>
spec:
  replicas: 1
  selector:
    matchLabels: {app: vllm, model: <model-alias>}
  template:
    metadata:
      labels: {app: vllm, model: <model-alias>}
    spec:
      serviceAccountName: <workload-identity-service-account>
      nodeSelector: {cloud.google.com/gke-accelerator: nvidia-l4}
      tolerations: [{key: nvidia.com/gpu, operator: Exists, effect: NoSchedule}]
      terminationGracePeriodSeconds: 120
      containers:
        - name: vllm
          image: <region>-docker.pkg.dev/<project>/<repo>/vllm-openai:v0.32.0
          args: ["--model=/models/<model>", "--revision=<immutable-commit-sha>",
                 "--served-model-name=<model-alias>", "--gpu-memory-utilization=0.90",
                 "--max-model-len=<context-limit>", "--enable-prefix-caching"]
          env:
            - name: VLLM_API_KEY
              valueFrom: {secretKeyRef: {name: <api-key-secret>, key: key}}
            - {name: HF_HUB_OFFLINE, value: "1"}
          ports: [{containerPort: 8000, name: http}]
          resources:
            requests: {nvidia.com/gpu: "1", cpu: "4", memory: 20Gi}
            limits: {nvidia.com/gpu: "1", memory: 24Gi}
          startupProbe: {httpGet: {path: /health, port: 8000}, periodSeconds: 10, failureThreshold: 60}
          readinessProbe: {httpGet: {path: /health, port: 8000}, periodSeconds: 10}
          volumeMounts:
            - {name: models, mountPath: /models, readOnly: true}
            - {name: shm, mountPath: /dev/shm}
      volumes:
        - name: models
          persistentVolumeClaim: {claimName: <model-weights-pvc>}
        - name: shm
          emptyDir: {medium: Memory, sizeLimit: 8Gi}
```

Mount a read-only model volume or GCS Fuse CSI and size `/dev/shm` for the selected model. The GKE startup probe accommodates model load time; set termination grace for draining streams. Confirm accelerator label, request/limit, PVC, and Secret Manager synchronization against the cluster before applying.

## Tune from measurements

| Goal | Tuning direction |
|---|---|
| Multi-GPU | `--tensor-parallel-size` for one node; evaluate pipeline parallelism for multi-node. |
| Lower memory | Quantization supported by the selected model/GPU; reduce context and `--max-num-seqs`. |
| Batch throughput | Increase sequence/batched-token capacity only while memory and p95 remain within target. |
| Interactive latency | Bound concurrency and queue depth; use streaming and keep a warm replica. |
| Long prompts | Evaluate chunked prefill and context limit against KV-cache headroom. |
| LoRA serving | Enable only approved adapters; keep adapter names and artifact revisions explicit. |

Flag names and model support change by release; use the pinned binary's `vllm serve --help` before changing behavior. Do not copy flags from a different version.

## Benchmark and diagnose

Use `vllm bench serve` against a running server and compare time-to-first-token, inter-token latency, p95, error rate, and tokens/s for a fixed prompt/concurrency sample. For CUDA OOM, lower context, concurrency, or memory utilization and re-measure. For queueing/KV pressure, reduce offered load or scale via `infra-llm-scaling-manage`; do not use GPU utilization as the only signal. For slow starts, pre-download immutable weights to persistent storage.