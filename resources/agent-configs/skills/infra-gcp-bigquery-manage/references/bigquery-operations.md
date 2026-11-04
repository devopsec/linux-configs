# BigQuery datasets, queries, and cost

Project, billing project, dataset/table IDs, location, classification, and retention are runtime inputs. A dataset’s location is a durable design choice; confirm all producers, consumers, and federated sources before creation.

## Dataset and access design

- Prefer dataset/table-scoped roles. Separate `roles/bigquery.jobUser` (submit jobs in the billing project) from data access (`roles/bigquery.dataViewer`, `roles/bigquery.dataEditor`, or narrower resource IAM where available).
- Avoid project-wide data owner/editor grants. Use authorized views or row/column policy controls for restricted fields instead of duplicating sensitive data.
- Align dataset location with data residency and supported query sources; do not assume a cross-region join is allowed.
- Set table/dataset expiration, retention, encryption policy, and audit-log routing deliberately. Ensure backups or time-travel windows meet recovery requirements before deleting data.

## Table layout

Partition large append/time-based tables by the query’s common filter dimension; cluster within partitions on frequently filtered or joined columns. Use partition filters and avoid partitioning tiny or high-churn data without measured benefit.

```sql
CREATE TABLE `PROJECT_ID.DATASET_ID.TABLE_ID` (
  event_timestamp TIMESTAMP,
  tenant_key STRING,
  event_type STRING,
  payload JSON
)
PARTITION BY DATE(event_timestamp)
CLUSTER BY tenant_key, event_type;
```

Use explicit schema evolution and expiration policy. Prefer typed columns for frequently queried fields; retain JSON for variable payloads only when the workload justifies it.

## Query cost and performance

Run dry-run before expensive queries, set a maximum bytes billed for interactive work, select only needed columns, filter partition columns early, and inspect execution graph/shuffle/slot time. A query that scans fewer bytes is generally faster and less costly. Avoid repeated full scans, unnecessary `ORDER BY`, and join fan-out.

```bash
bq query --project_id="$BILLING_PROJECT" --location="$LOCATION" \
  --use_legacy_sql=false --dry_run \
  'SELECT event_timestamp, event_type FROM `PROJECT_ID.DATASET_ID.TABLE_ID` WHERE DATE(event_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY)'

bq query --project_id="$BILLING_PROJECT" --location="$LOCATION" \
  --use_legacy_sql=false --maximum_bytes_billed="$MAX_BYTES" \
  'SELECT event_type, COUNT(*) FROM `PROJECT_ID.DATASET_ID.TABLE_ID` WHERE DATE(event_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY) GROUP BY event_type'
```

For predictable monthly spend or sustained concurrency, compare on-demand with reservation-based capacity using measured slot utilization; do not purchase capacity from a single slow query without reviewing its plan.

## Observe jobs

Use job history and query plan to identify high bytes processed, slot time, shuffle, errors, and contention. Restrict regional `INFORMATION_SCHEMA` views to the job location and avoid querying unbounded history.

```sql
SELECT job_id, user_email, total_bytes_processed, total_slot_ms, error_result
FROM `region-LOCATION`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY total_bytes_processed DESC
LIMIT 100;
```

## Destructive changes and recovery

Before dropping/truncating a table, changing expiration, or replacing a dataset, check downstream dependencies, scheduled queries, access policies, retention, and recovery windows. Prefer a snapshot/clone or a staged replacement where available. Require explicit approval before irreversible data operations.

Cloud Build use follows the same principle as the repository’s pipeline: PR validation is non-publishing and should not mutate production data; runtime data writers must use dedicated identities. Keep SQL validation and deployment separate from data processing.

## References

- [BigQuery query performance overview](https://cloud.google.com/bigquery/docs/best-practices-performance-overview) — documentation last updated 2026-10-22; checked 2026-10-28.
- [BigQuery IAM](https://cloud.google.com/bigquery/docs/access-control) — checked 2026-10-28.
- [BigQuery partitioned tables](https://cloud.google.com/bigquery/docs/partitioned-tables) — checked 2026-10-28.