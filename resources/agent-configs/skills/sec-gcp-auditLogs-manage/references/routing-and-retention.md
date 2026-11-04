# Audit log routing, analysis, and retention

## Choose a destination

| Destination | Best for | Control to verify |
|---|---|---|
| Partitioned BigQuery dataset | Analysis, joins, compliance evidence | Dataset IAM, location, partition expiration, query access |
| Cloud Storage archive | Long-term immutable evidence | Uniform bucket access, public access prevention, CMEK, retention policy |
| Pub/Sub | Real-time SIEM consumers | Writer identity, publisher scope, message retention, dead-letter handling |
| Log bucket with analytics | SQL in Logs Explorer | Bucket location, retention, linked dataset access |

Prefer a dedicated logging project and least-privilege sink writer identity. Use aggregated organization/folder sinks only when the scope and destination are approved.

## BigQuery sink

Create a dedicated dataset in the required data-residency location, enable partitioned tables, and grant the sink writer only the dataset role it needs:

```bash
gcloud logging sinks create "<sink-name>" \
  "bigquery.googleapis.com/projects/${LOGGING_PROJECT}/datasets/${AUDIT_DATASET}" \
  --project="${SCOPE_PROJECT}" --use-partitioned-tables \
  --log-filter='logName:"cloudaudit.googleapis.com"'
```

For organization or folder scope, use the matching scope flag and include descendants only when approved. Resolve the generated writer identity and grant dataset access through the approved IAM mechanism. Verify sink errors; missing writer permissions can silently drop entries.

Filter by `timestamp` first in BigQuery queries to prune partitions. Use `bq query --dry_run` before expensive analysis. Validate table names and schemas in the destination rather than assuming suffix conventions.

## Archive and stream

For Cloud Storage, configure uniform access, public access prevention, encryption, and the required retention policy before creating the sink. A retention lock is irreversible: test on a disposable bucket and obtain explicit approval before locking it. Do not set a retention duration without the applicable legal, contractual, and operational policy.

Use Pub/Sub only when an approved consumer requires near-real-time delivery. Scope the sink publisher to the topic, configure message retention and dead-letter behavior, and monitor subscription health.

## Infrastructure as code

Keep datasets, sinks, destination IAM, retention, and alerting in reviewed infrastructure as code. For a locked archive, keep the lock disabled in the initial plan and require a separate reviewed approval before enabling it. Prevent accidental destruction; do not use force-destroy for evidence destinations.

## Retention and privacy

There is no universal retention period for every audit record. Confirm applicable law, contract, customer commitments, data residency, and investigation needs with the data owner and counsel. Keep CDRs and other high-risk business data in their approved data systems rather than copying them into general security audit datasets. Minimize personal data and document deletion/expiry behavior.