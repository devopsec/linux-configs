# Google Cloud Audit Logs

## Log types

| Type | Purpose | Default behavior |
|---|---|---|
| Admin Activity | Administrative changes | Always enabled; stored in `_Required` |
| System Event | Google Cloud system actions | Always enabled; stored in `_Required` |
| Policy Denied | Denied operations | Enabled; destination/retention depend on configuration |
| Data Access | Reads and writes of customer data | Often disabled by default; configure explicitly |

Data Access categories include `ADMIN_READ`, `DATA_READ`, and `DATA_WRITE`. Organization, folder, and project settings combine by inheritance; a child policy cannot negate a parent requirement. Review the current Cloud Logging retention and billing behavior for the destination before changing policy.

## Enable Data Access with infrastructure as code

Prefer a single owned module for audit configuration to avoid conflicts with authoritative IAM policy resources:

```hcl
resource "google_project_iam_audit_config" "sensitive_service" {
  project = var.project_id
  service = "<service-api>"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
```

Use service-specific configuration for sensitive APIs and an approved `ADMIN_READ` baseline where appropriate. Exemptions should be narrow, justified, and reviewed; noisy principals are not a reason to disable a whole service's Data Access logs.

## Manual fallback

Only use manual policy editing when infrastructure as code is unavailable. Fetch the current policy immediately before editing, preserve its `etag` and bindings, merge the `auditConfigs` field, and review the complete result before applying. `set-iam-policy` replaces the entire policy; a stale file can erase unrelated access controls.

```bash
gcloud projects get-iam-policy "${PROJECT_ID}" --format=json >"${POLICY_FILE}"
# Merge only the required auditConfigs; preserve bindings and etag.
gcloud projects set-iam-policy "${PROJECT_ID}" "${POLICY_FILE}"
gcloud projects get-iam-policy "${PROJECT_ID}" --format=json | jq '.auditConfigs'
```

## Querying

Use bounded time windows and select only needed fields:

```bash
gcloud logging read \
  'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName="SetIamPolicy"' \
  --project="${PROJECT_ID}" --freshness="<duration>" \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)'
```

For long windows or cross-project analysis, route logs to an authorized query destination and apply partition/time filters. Data Access configuration, ingestion, and query costs should be estimated before broadening scope.