# BigQuery backup and restore reference

Checked against Google Cloud documentation on 2026-10-28: BigQuery time travel is configurable from 2 to 7 days (default 7); the additional fail-safe period is 7 days and is not configurable. Confirm the dataset's actual setting and current service documentation before a recovery decision.

## Recovery layers

| Mechanism | Use | Boundaries |
|---|---|---|
| Time travel | Read or copy recent table state after edits/deletes | Dataset-specific window, service permissions, and region constraints apply |
| Table snapshot | Retain a point-in-time table image beyond the time-travel window | Requires an explicit expiration/retention decision and cost review |
| Export to separate storage | Independent logical copy and project-level failure separation | Validate export completeness, storage permissions, encryption, and import path |
| Cross-region dataset replication / managed DR | Regional resilience and workload failover | Feature and outage limitations apply; replication alone is not a complete DR plan |
| Fail-safe | Emergency recovery after the time-travel window | Not a self-service backup; contact the provider promptly and do not treat it as guaranteed recovery |

## Read or copy a historical table

Use a new destination and validate it before switching consumers. Set the point in time and matching offset from an approved recovery decision; validate the timestamp and all identifiers before use:

```bash
bq query --use_legacy_sql=false \
  "SELECT COUNT(*) FROM \`$PROJECT.$DATASET.$TABLE\` FOR SYSTEM_TIME AS OF TIMESTAMP('$AS_OF_UTC')" &&
bq cp "$PROJECT:$DATASET.$TABLE@-$OFFSET_MS" "$PROJECT:$DATASET.${TABLE}_restored" &&
bq show --format=prettyjson "$PROJECT:$DATASET"
```

Set the requested timestamp/offset from an approved recovery decision. Verify the table's historical availability and destination region; do not use a forced copy onto the live table.

## Deleted datasets, snapshots, and exports

Undelete a dataset only within its time-travel window and in its original location. Confirm the dataset ID/location and obtain approval before this state-changing recovery:

```sql
UNDROP SCHEMA `project_name.dataset_name` OPTIONS (location = "region-or-multi-region");
```

For snapshots, apply the approved expiry rather than using an example retention as a default. Validate `PROJECT`, dataset IDs, and timestamps from approved configuration:

```bash
SNAPSHOT_ID="${TABLE}_$(date -u +%Y%m%d)" &&
bq cp --snapshot --no_clobber --expiration="$SNAPSHOT_EXPIRY_SECONDS" \
  "$PROJECT:$DATASET.$TABLE" "$PROJECT:$SNAPSHOT_DATASET.$SNAPSHOT_ID" &&
bq cp --no_clobber "$PROJECT:$SNAPSHOT_DATASET.$SNAPSHOT_ID" \
  "$PROJECT:$DATASET.${TABLE}_from_snapshot"
```

The `bq cp --restore` flag is deprecated; copying the snapshot to a new table creates a writable table. Do not copy a snapshot over a live destination during an assessment or drill.

For exports, use an approved format such as Avro/Parquet and keep the target outside the primary data project's failure boundary where policy allows. Test loading the export into a new table. For regional resilience, evaluate cross-region replication or managed DR against the current service's limitations and a tested workload failover plan. As documented on 2026-10-28, cross-region replication alone cannot be promoted during a complete outage of the primary region; do not use it as a total-region DR guarantee.

BigQuery table recovery restores the table, not an individual partition through a time-travel table decorator. If only selected partitions are needed, restore the table to a new name, then copy the approved partition data using a validated query/job.

## Pub/Sub ingestion recovery

The subscription message-retention default for unacknowledged messages is 7 days, with a maximum of 31 days; replay of acknowledged messages requires the relevant retention option to be enabled. These values were checked 2026-10-28. Confirm topic and subscription settings before relying on replay, then seek/replay into a repaired table and validate duplicates, ordering, and idempotency. Do not assume BigQuery retention implies that the source messages remain available.

## Validation and safety

- Compare schema, partitioning/clustering, row counts, representative query results, IAM, labels, and downstream jobs.
- Check CMEK availability and access in the restore region; loss of a key can make a copy unusable.
- Treat replacement/force flags as destructive. Restore to a new name, validate, then use an approved cutover and rollback plan.
- Apply deletion and retention obligations to snapshots and exports, not just active tables.

Official references: [BigQuery time travel and fail-safe](https://cloud.google.com/bigquery/docs/time-travel), [restore deleted datasets](https://cloud.google.com/bigquery/docs/restore-deleted-datasets), [table snapshots](https://cloud.google.com/bigquery/docs/table-snapshots-restore), [cross-region replication](https://cloud.google.com/bigquery/docs/data-replication), and [Pub/Sub subscription retention](https://cloud.google.com/pubsub/docs/subscription-message-retention). Service-window and Pub/Sub retention values were checked 2026-10-28.