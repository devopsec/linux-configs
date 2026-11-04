# OpenTelemetry for Python services → Google Cloud Observability

## Contents

1. Architecture choices
2. Python: zero-code instrumentation (uv)
3. Python: manual spans, metrics, log correlation
4. systemd wiring
5. Collector on a VM (otelcol-contrib)
6. Ops Agent alternative
7. Sampling, cardinality, redaction
8. Validation & troubleshooting

## 1. Architecture choices

| Option | When | Notes |
|---|---|---|
| App → local **Ops Agent** (OTLP receiver) → Cloud Trace/Monitoring/Logging | GCE VMs already running Ops Agent | least moving parts; agent handles auth via VM service account |
| App → local **otelcol-contrib** → `googlecloud` / `googlemanagedprometheus` exporters | need processors (tail sampling, redaction, routing) or multiple backends | one collector per VM (agent) or a small gateway pool |
| App → OTLP directly to Google's Telemetry API (`telemetry.googleapis.com`) | no local agent possible | verify current endpoint/auth docs; needs ADC credentials in-process |

IAM for the VM service account (least privilege): `roles/cloudtrace.agent`, `roles/monitoring.metricWriter`, `roles/logging.logWriter`. Provision via OpenTofu → `infra-gcp-any-manage`.

Reference pin: otelcol-contrib **0.163.2**, checked 2026-10-28 against the [official collector releases](https://github.com/open-telemetry/opentelemetry-collector-releases/releases). Python SDK/API and instrumentation packages are versioned independently; pin the selected compatible set in `uv.lock`.

## 2. Python: zero-code instrumentation (uv)

```bash
uv add opentelemetry-distro opentelemetry-exporter-otlp
uv run opentelemetry-bootstrap --action=requirements > "$TMPDIR/otel-req.txt"   # lists instrumentations for installed libs
uv add -r "$TMPDIR/otel-req.txt"                                                 # review the list first
uv run opentelemetry-instrument python -m <package>.main
```

Config by env (no code changes):

```bash
OTEL_SERVICE_NAME=<service>
OTEL_RESOURCE_ATTRIBUTES=service.version=<git-sha-or-version>,deployment.environment.name=<prod|stage>
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317     # local agent/collector only; use TLS for anything off-host
OTEL_EXPORTER_OTLP_PROTOCOL=grpc
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=true
OTEL_PYTHON_EXCLUDED_URLS=healthz,readyz,metrics
```

Gotchas: pre-fork servers (gunicorn/uwsgi) need SDK init in the `post_fork` hook, not the master; `asyncio`/`psycopg`/`sqlalchemy`/`requests`/`httpx`/`flask`/`fastapi` all have instrumentations — don't add both manual and auto for the same library (duplicate spans).

## 3. Python: manual spans, metrics, log correlation

```python
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def init_telemetry() -> None:
    """Configure global tracer/meter providers from OTEL_* env vars."""
    resource = Resource.create()  # reads OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES
    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))  # endpoint from env
    trace.set_tracer_provider(tracer_provider)
    reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=30_000)
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))


tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)
operations_total = meter.create_counter("app.operations", unit="{operation}", description="Processed operations")
operation_duration = meter.create_histogram("app.operation.duration", unit="s")


def process(operation_category: str) -> None:
    with tracer.start_as_current_span("process_operation") as span:
        span.set_attribute("app.operation_category", operation_category)   # bounded values only
        operations_total.add(1, {"operation_category": operation_category})
```

- Call `provider.shutdown()` on SIGTERM so batches flush (systemd sends SIGTERM first).
- Record exceptions: `span.record_exception(exc); span.set_status(StatusCode.ERROR)`.
- Log ↔ trace correlation in Cloud Logging: emit JSON with `logging.googleapis.com/trace = "projects/<project>/traces/<trace_id>"`, `logging.googleapis.com/spanId`, `logging.googleapis.com/trace_sampled`. With OTLP logs via the collector/Ops Agent this mapping is done for you.

## 4. systemd wiring

```ini
# /etc/systemd/system/<service>.service.d/otel.conf
[Service]
EnvironmentFile=/etc/<service>/otel.env
ExecStart=
ExecStart=/opt/<service>/.venv/bin/opentelemetry-instrument /opt/<service>/.venv/bin/python -m <package>.main
```

Keep the protected environment file in the service's deployment templates/configuration management; reload the service manager and restart only when the unit change requires it.

## 5. Collector on a VM (otelcol-contrib)

Install the signed package from the `opentelemetry-collector-releases` GitHub release: use the reference pin `0.163.2` or another explicitly selected release; download the matching `otelcol-contrib_<ver>_linux_amd64.rpm|deb` **and** its `.sha256`, verify (`sha256sum --check`) and optionally `cosign verify-blob` with the `.sigstore.json` bundle, then install through the distro package manager. Config at `/etc/otelcol-contrib/config.yaml`.

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 127.0.0.1:4317 }
      http: { endpoint: 127.0.0.1:4318 }
  hostmetrics:
    collection_interval: 60s
    scrapers: { cpu: {}, memory: {}, disk: {}, filesystem: {}, network: {}, load: {} }

processors:
  memory_limiter: { check_interval: 1s, limit_percentage: 75, spike_limit_percentage: 15 }
  resourcedetection: { detectors: [env, gcp, system], timeout: 5s }
  transform/scrub:
    trace_statements:
      - context: span
        statements:
          - replace_pattern(attributes["url.full"], "(?i)(token|key|password)=[^&]*", "$$1=REDACTED")
  batch: { send_batch_size: 1024, timeout: 5s }

exporters:
  googlecloud:
    log: { default_log_name: otel }
  googlemanagedprometheus: {}

extensions:
  health_check: { endpoint: 127.0.0.1:13133 }

service:
  extensions: [health_check]
  telemetry:
    metrics:
      readers:
        - pull: { exporter: { prometheus: { host: 127.0.0.1, port: 8888 } } }
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, resourcedetection, transform/scrub, batch], exporters: [googlecloud] }
    metrics: { receivers: [otlp, hostmetrics], processors: [memory_limiter, resourcedetection, batch], exporters: [googlemanagedprometheus] }
    logs:    { receivers: [otlp], processors: [memory_limiter, resourcedetection, batch], exporters: [googlecloud] }
```

- Order: `memory_limiter` first, `batch` last.
- Upstream used `0.0.0.0` listeners + `tls.insecure: true` to remote backends — bind to loopback; any cross-host OTLP must use TLS (+ mTLS or bearer token from env: `headers: { authorization: "Bearer ${env:OTLP_TOKEN}" }`).
- Validate: `otelcol-contrib validate --config=/etc/otelcol-contrib/config.yaml`.

## 6. Ops Agent alternative

`/etc/google-cloud-ops-agent/config.yaml` (merge with existing; verify keys against current Ops Agent docs):

```yaml
combined:
  receivers:
    otlp:
      type: otlp
      grpc_endpoint: 127.0.0.1:4317
      metrics_mode: googlemanagedprometheus
metrics:
  service:
    pipelines:
      otlp: { receivers: [otlp] }
traces:
  service:
    pipelines:
      otlp: { receivers: [otlp] }
```

`systemctl restart google-cloud-ops-agent`; logs in `journalctl -u google-cloud-ops-agent*`. Ops Agent can also scrape Prometheus-compatible service endpoints (`type: prometheus` receiver) when a separate Prometheus server is unnecessary.

## 7. Sampling, cardinality, redaction

- Head sampling in SDK (`parentbased_traceidratio`) for volume; tail sampling in collector when you must keep all errors/slow traces:

```yaml
processors:
  tail_sampling:
    decision_wait: 10s
    num_traces: 50000
    policies:
      - { name: errors, type: status_code, status_code: { status_codes: [ERROR] } }
      - { name: slow, type: latency, latency: { threshold_ms: 2000 } }
      - { name: baseline, type: probabilistic, probabilistic: { sampling_percentage: 10 } }
```

  Tail sampling needs all spans of a trace on the same collector (single gateway or `loadbalancing` exporter by trace ID).
- Metric attributes: bounded sets only (route template, status class, operation category). Normalise paths (`/users/{id}`) in instrumentation or `transform`.
- Never put secrets, auth headers, personal identifiers, or raw URL values in span attributes or logs; scrub in the collector as defence in depth.

## 8. Validation & troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| nothing in Cloud Trace | collector logs `journalctl -u otelcol-contrib`; IAM `cloudtrace.agent` | grant role / correct project via `resourcedetection` |
| `PermissionDenied` on metrics | `monitoring.metricWriter` missing | grant role |
| broken traces across services | proxy strips `traceparent` | forward W3C headers |
| collector OOM | tail-sampling buffers | lower `num_traces`, raise `memory_limiter` limit |
| duplicate spans | manual + auto instrumentation | pick one per library |
| no spans from gunicorn workers | SDK initialised pre-fork | init in `post_fork` |

Local debug: add `debug: { verbosity: detailed }` exporter temporarily to a pipeline; remove after.
