# GCP audit-event alerts

## Detection patterns

| Detection | Example Cloud Logging filter | Suggested signal |
|---|---|---|
| IAM policy change | `protoPayload.methodName="SetIamPolicy"` | Per-event alert |
| Service-account key creation/upload | `protoPayload.methodName:("google.iam.admin.v1.CreateServiceAccountKey" OR "google.iam.admin.v1.UploadServiceAccountKey")` | Per-event alert |
| Firewall/network change | `protoPayload.methodName:("compute.firewalls." OR "compute.networks." OR "compute.routes.")` | Per-event alert |
| Sink, bucket, or exclusion change | `protoPayload.serviceName="logging.googleapis.com" AND protoPayload.methodName:("Sink" OR "Bucket" OR "Exclusion")` | Per-event tamper alert |
| Audit configuration change | `protoPayload.methodName="SetIamPolicy" AND protoPayload.serviceData.policyDelta.auditConfigDeltas:*` | Per-event alert |
| Secret access spike | `protoPayload.serviceName="secretmanager.googleapis.com" AND protoPayload.methodName:"AccessSecretVersion"` | Metric and threshold |
| Permission-denied burst | `protoPayload.status.code=7` | Metric and threshold |

Validate field paths against actual events in the target log bucket; parsed fields may differ by source and destination.

## Discrete event alerts

Create a log-based alert for a high-value event where each match merits review. Keep the message actionable and identify the verification steps and response owner:

```json
{
  "displayName": "<detection-name>",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "<condition-name>",
      "conditionMatchedLog": {
        "filter": "<validated-cloud-logging-filter>"
      }
    }
  ],
  "notificationChannels": ["projects/<project>/notificationChannels/<channel-id>"],
  "documentation": {
    "content": "<response guidance without secrets>",
    "mimeType": "text/markdown"
  }
}
```

Policies evaluate in the project where the logs are stored. For organization-wide coverage, route the relevant events to a central project and create the policy there.

## Rate-based signals

Use a log-based metric for event volume or bursts. Baseline by principal and workload before setting a paging threshold; a fixed threshold without a normal-volume model will either miss abuse or create noise. Use an aggregation window appropriate to the threat and document how the on-call responder should validate the signal.

## Deployment and testing

Manage metrics and policies through reviewed infrastructure as code when available. Store notification secrets outside policy files and grant access only to the delivery component. Test with a harmless event in an approved sandbox, confirm policy evaluation and delivery on each channel, and record the test date and incident reference.

Monitor the alerting path itself: sink errors, missing log ingestion, disabled policies, and notification delivery failures should generate an operational signal.