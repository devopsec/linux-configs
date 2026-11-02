# Cloud SQL for PostgreSQL

Project ID, region, VPC, database name, sizing, maintenance window, and recovery targets are runtime inputs. Cloud SQL documentation last updated 2026-10-22 lists PostgreSQL `18.6` as the default major/minor; `POSTGRES_18` is an example major checked 2026-10-28, not a universal app default. Match the database major to application and extension compatibility.

## Private network and instance baseline

Use Private Services Access (PSA) or Private Service Connect (PSC) for private connectivity. PSA consumes a reserved VPC range that must not overlap subnet or on-prem routes; peering is non-transitive. Enable the SQL Admin and Service Networking APIs and confirm the private connection is ready before creating an instance.

PSA is configured once per VPC; reserve a non-overlapping range and take its prefix length from the network plan rather than copying a sample value:

```bash
gcloud services enable sqladmin.googleapis.com servicenetworking.googleapis.com --project="$PROJECT_ID"
gcloud compute addresses create "$PSA_RANGE_NAME" --project="$PROJECT_ID" \
  --global --purpose=VPC_PEERING --prefix-length="$PSA_PREFIX_LENGTH" --network="$VPC"
gcloud services vpc-peerings connect --project="$PROJECT_ID" \
  --service=servicenetworking.googleapis.com --ranges="$PSA_RANGE_NAME" --network="$VPC"
```

```bash
gcloud sql instances create "$INSTANCE" \
  --project="$PROJECT_ID" --database-version="$DATABASE_VERSION" --edition=ENTERPRISE \
  --region="$REGION" --availability-type="$AVAILABILITY" \
  --network="projects/${PROJECT_ID}/global/networks/${VPC}" --no-assign-ip \
  --ssl-mode=ENCRYPTED_ONLY --deletion-protection
```

Use regional HA for production availability requirements and zonal instances only where the recovery objective permits. Set backup retention, PITR, maintenance windows, storage auto-growth limits, and deletion protection deliberately. Apply the full intended flag set: a flags patch replaces the existing list.

For a new managed PostgreSQL instance, `POSTGRES_18` is currently the documented default major; a selected major must be checked against app extensions and migration support. Cloud SQL controls minor updates, so schedule maintenance and test client compatibility rather than pinning a minor in the create command.

## Authentication and connection

- Prefer Cloud IAM database authentication for applications. Grant `roles/cloudsql.client` and, where IAM DB auth is used, `roles/cloudsql.instanceUser` to the runtime identity.
- For password-based users, generate credentials outside IaC and keep the secret only in Secret Manager; rotate through a controlled process.
- Prefer private IP plus TLS from same-VPC clients, Cloud SQL Auth Proxy, or a language connector. Avoid public IP and authorized networks except time-limited administration.
- Cloud Run can use Direct VPC egress, a Serverless VPC Access connector, or the Cloud SQL integration where supported.

Create IAM database users with an IAM identity and grant database-level SQL privileges through the database administrator process. A Google Cloud IAM role alone does not grant access to SQL tables.

Cloud SQL Auth Proxy `2.26.3` (checked 2026-10-28) may be installed from the pinned release artifact after checksum verification:

```bash
VER=2.26.3
curl -fsSLo cloud-sql-proxy \
  "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v${VER}/cloud-sql-proxy.linux.amd64"
printf '%s  %s\n' \
  '5533a05cdbf12f8a0cb46db34c775847a496e181d47f863284d3d02b0fad49fa' \
  'cloud-sql-proxy' | sha256sum -c -
```

Use the proxy with a dedicated runtime identity and `--private-ip` for private-only instances. Run it as a dedicated service account/systemd unit with restricted filesystem access; do not embed credentials in unit files.

## Replicas, backups, and recovery

Create a backup before planned maintenance or data migration. Use PITR by cloning to a new instance and validate the result before cutover. Test restore procedures periodically.

```bash
gcloud sql backups create --project="$PROJECT_ID" --instance="$INSTANCE" --description="$BACKUP_REASON"
gcloud sql backups list --project="$PROJECT_ID" --instance="$INSTANCE"
gcloud sql instances clone "$INSTANCE" "$RESTORE_CLONE" --project="$PROJECT_ID" \
  --point-in-time="$RECOVERY_TIMESTAMP"
```

For a cross-region read replica or analytics export, confirm region, data residency, IAM on the destination bucket, and replication lag before cutover. Promote a replica only after primary-loss confirmation; promotion is irreversible. Restore into a new clone first; restoring onto an existing target overwrites target data.

**Destructive/high impact:** replica promotion breaks replication; restore overwrites target data; import writes into a live database; deletion removes the instance. Confirm source, target, latest backup, and rollback path before action.

## Inspection and troubleshooting

```bash
gcloud sql instances describe "$INSTANCE" --project="$PROJECT_ID"
gcloud sql operations list --project="$PROJECT_ID" --instance="$INSTANCE"
gcloud sql backups list --project="$PROJECT_ID" --instance="$INSTANCE"
```

| Symptom | Check |
|---|---|
| PSA/network not ready | API enablement, reserved-range overlap, and peering status. |
| Proxy authorization denied | Runtime IAM roles, enabled API, and target instance name. |
| Proxy cannot connect to private address | `--private-ip`, VPC routing, DNS, and client egress. |
| TLS rejected | Instance SSL mode and client/proxy transport settings. |
| Connection flags changed unexpectedly | Patch replaced the full flag set; reapply the complete intended set. |

## References

- [Cloud SQL for PostgreSQL documentation](https://cloud.google.com/sql/docs/postgres) — checked 2026-10-28.
- [PostgreSQL supported versions](https://cloud.google.com/sql/docs/postgres/db-versions) — documentation last updated 2026-10-22; checked 2026-10-28.
- Cloud SQL Auth Proxy release `v2.26.3`, published 2026-10-22; checksum from the [official release](https://github.com/GoogleCloudPlatform/cloud-sql-proxy/releases/tag/v2.26.3).