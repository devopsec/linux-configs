# ML/LLM pipeline orchestration

## Contents

- Version pins and orchestrator selection
- Idempotency, retries, secrets, and evaluation gates
- Prefect, Airflow 3, and Dagster examples
- GCP-native pipelines and release validation

Versions checked 2026-10-28: Prefect `3.9.0`, Apache Airflow `3.3.2`, Dagster `1.13.27`. Pin core and provider packages together in the project lockfile; for Airflow use its matching constraints file. Cloud-managed service versions are selected from the provider's supported matrix, not inferred from the open-source package pin.

## Choose the smallest suitable orchestrator

| Choice | Prefer when |
|---|---|
| GCP-native Workflows + Cloud Run Jobs/Batch or Vertex AI Pipelines | A few event/scheduled pipelines; avoid operating another scheduler. |
| Prefect 3 | Python-first dynamic flows and a small-to-medium team. |
| Airflow 3 / Cloud Composer | Existing DAG estate, many schedules, or established Airflow operations. |
| Dagster | Asset lineage, partitions, materialization, and data-quality checks are central. |
| Temporal | Long-running stateful workflows or human approvals are core; it is not usually needed for ordinary ETL. |

Separate ingestion, training, evaluation, and deployment. Pass versioned artifacts (private object URIs/model registry IDs) between tasks rather than coupling everything into one DAG.

## Reliability contract

- Make each task idempotent using content hash, partition, or job key; retries of non-idempotent side effects require deduplication.
- Bound retries/backoff and concurrency to provider RPM/TPM and database limits; add deadlines and cancellation.
- Keep thresholds/configuration separate from code; evaluation failure must block artifact promotion.
- Route secrets through the orchestrator's managed secret backend/Workload Identity; do not put tokens in DAG code or task parameters.
- Emit per-run input/output counts, skipped/failed records, duration, tokens/cost, and artifact version.

## Prefect example

```bash
uv add 'prefect==3.9.0'
```

For local development, run the server in a separate terminal:

```bash
prefect server start
```

After the server or cloud workspace is reachable, create the Kubernetes work pool:

```bash
prefect work-pool create '<pool-name>' --type kubernetes
```

Start a worker in a separate terminal or managed workload:

```bash
prefect worker start --pool '<pool-name>'
```

Use Prefect 3 `cache_policy` for deterministic task inputs; do not reuse deprecated Prefect 2 caching examples. Hash source documents and upsert vectors by deterministic ID so a replay is safe. Put batch LLM concurrency behind a global limit and write outputs to a versioned location.

Minimal flow shape:

```python
from datetime import timedelta
from prefect import flow, task
from prefect.cache_policies import INPUTS

@task(retries=2, retry_delay_seconds=30, cache_policy=INPUTS,
      cache_expiration=timedelta(hours=24))
def ingest_partition(source_uri: str) -> str:
    return process_idempotently(source_uri)

@flow(name='daily-ingestion')
def run(source_uri: str) -> str:
    return ingest_partition(source_uri)
```

## Airflow 3 / Dagster

Airflow 3 DAG authoring uses `airflow.sdk`; pin the matching Kubernetes provider and use `KubernetesPodOperator` for isolated GPU jobs. In Composer, use a supported Composer image and provider set rather than installing arbitrary packages into the scheduler. Evaluate `service_account_name`, GPU selector/quota, `on_finish_action`, and artifact path before launch.

```python
from airflow.sdk import dag, task
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator

@dag(dag_id='model_training', schedule=None, catchup=False)
def model_training():
    train = KubernetesPodOperator(
        task_id='train', namespace='<namespace>', name='trainer',
        image='<region>-docker.pkg.dev/<project>/<repo>/trainer@sha256:<digest>',
        cmds=['python', '-m', 'train'], service_account_name='<workload-identity>',
        on_finish_action='delete_pod', get_logs=True,
    )

model_training()
```

Dagster asset dependencies should flow through asset inputs or explicit `deps`, not both. Attach run metadata such as row/chunk count, quality score, and source snapshot to materializations.

```python
from dagster import AssetExecutionContext, asset

@asset
def raw_documents() -> list[dict]:
    return fetch_versioned_sources()

@asset
def document_embeddings(context: AssetExecutionContext,
                        raw_documents: list[dict]) -> int:
    count = embed_and_upsert(raw_documents)
    context.add_output_metadata({'chunks': count})
    return count
```

## GCP-native and release gates

- GCS finalize → Pub/Sub → Cloud Run Job/worker for event ingestion; Cloud Scheduler → Workflows → Cloud Run Jobs/Batch for scheduled work.
- Use Vertex AI Pipelines/custom jobs when managed ML execution/model registry is required; keep data and artifacts region-aligned and private.
- Build/publish pipeline images via reviewed CI, pin the image digest, run unit/lint tests on task code, and deploy definitions through a controlled release path.
- Validate fresh run, retry, duplicate event, partial failure, cancellation, evaluation rejection, and resume from checkpoint before production scheduling.