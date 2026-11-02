# Google Cloud Storage operations

## CLI and identity

Prefer `gcloud storage` for new workflows; treat `gsutil` as a compatibility dependency and migrate existing scripts deliberately. Use ADC or service-account impersonation/workload identity rather than long-lived service-account keys.

```bash
gcloud auth list
gcloud storage buckets describe gs://<bucket>
gcloud storage ls -l -r gs://<bucket>/<prefix>/
```

Bucket names are globally visible identifiers. Do not include customer names or secrets in them. Keep bucket and consumer in compatible locations to avoid latency and transfer costs.

## Secure bucket baseline

```bash
gcloud storage buckets create gs://<bucket> \
  --project=<project> --location=<location> \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets describe gs://<bucket> \
  --format='yaml(location,iamConfiguration,softDeletePolicy,versioning,lifecycle,encryption)'
```

Prefer uniform bucket-level access, public access prevention, and service-account identity. Grant the narrowest role at the bucket or required prefix. Review IAM Conditions and organization policies before broadening access.

| Access need | Typical role |
|---|---|
| Read objects | `roles/storage.objectViewer` |
| Create objects without reading/deleting | `roles/storage.objectCreator` |
| Read/write object data | `roles/storage.objectUser` |
| Change bucket policy/settings | `roles/storage.admin` only for operators/IaC |

```bash
gcloud storage buckets add-iam-policy-binding gs://<bucket> \
  --member=serviceAccount:<service-account> --role=roles/storage.objectViewer
gcloud storage buckets get-iam-policy gs://<bucket>
```

## Versioning, soft delete, retention, and CMEK

Enable object versioning or soft delete according to recovery and cost requirements; lifecycle noncurrent generations deliberately. A retention policy prevents deletion until its period expires. Locking a retention policy is irreversible and requires explicit compliance approval.

For CMEK, grant the GCS service agent the required KMS use permission and set the bucket default key only after confirming compatible locations and key lifecycle. Disabling or destroying the key can make protected objects unreadable.

Do not invent retention durations, lifecycle ages, bucket locations, or KMS key identifiers. Ask for the approved values and verify effective settings after applying them.

## Object operations

```bash
gcloud storage cp <local-file> gs://<bucket>/<prefix>/<object>
gcloud storage cp -r gs://<bucket>/<prefix>/ <restore-directory>/
gcloud storage rsync <source> <destination> --recursive --dry-run
```

Review the dry-run output before running a sync that deletes or replaces destination objects. For large-scale transfers, use a managed transfer service rather than a client-side loop. Verify object generation, metadata, ownership, and application read access after a transfer.

Signed URLs are bearer credentials: keep duration minimal, never log the URL, and use an authorized signing identity. Do not put signing key material in the skill or a command transcript.

## S3-compatible interoperability boundary

GCS offers an XML API for some S3-compatible clients and supports HMAC credentials for interoperability. Prefer native `gcloud storage`/client integrations. Create HMAC credentials only when a consumer requires them, store the secret in Secret Manager, rotate/revoke it under the owner's process, and never include the secret in shell history or configuration examples. For legacy MinIO, treat it as an external S3-compatible client/backend; assess its maintenance and licensing status before adoption, but keep MinIO operations in a dedicated skill. AWS S3 bucket policy, lifecycle, and EBS administration belong to the AWS storage skill.

## Notifications and audit

Use Cloud Audit Logs/Data Access logs for sensitive object access, understanding that data-access logging can increase log volume and cost. Bucket notifications require a separately authorized Pub/Sub topic; validate publisher identity and delivery behavior with the messaging owner.

## Troubleshooting

| Symptom | Check |
|---|---|
| Access denied | active principal, bucket IAM, conditions, VPC Service Controls, KMS key grants |
| Public access blocked | public access prevention; use approved signed access or an authorized CDN path |
| Object cannot be deleted | retention policy, hold, generation, soft-delete state |
| Unexpected storage cost | old generations, soft-delete retention, lifecycle rules, location/egress |
| Slow transfer | consumer/bucket locations, concurrency, network path, object size distribution |