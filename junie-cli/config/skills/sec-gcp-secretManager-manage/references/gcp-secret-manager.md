# GCP Secret Manager

## Create and version

Create a secret container without a value, then add the payload through stdin so it does not appear in command arguments or shell history:

```bash
gcloud secrets create "${SECRET_ID}" \
  --project="${PROJECT_ID}" --replication-policy=automatic
read -rs SECRET_VALUE
printf '%s' "${SECRET_VALUE}" | gcloud secrets versions add "${SECRET_ID}" \
  --project="${PROJECT_ID}" --data-file=-
unset SECRET_VALUE
```

Use user-managed replication only when residency requires it. Keep identifiers generic and use labels for owner, environment, and service where policy permits.

## IAM and consumption

Grant `roles/secretmanager.secretAccessor` on the individual secret to its workload service account. Use attached identities on VMs and the designated build identity in Cloud Build; do not create exported service-account keys. For Cloud Build, declare the secret through `availableSecrets` and expose it only to the step that needs it. For systemd services, fetch at startup into a protected runtime location or use a systemd credential mechanism; never bake a value into an image, unit file, install script, or Terraform state.

Check IAM without reading payloads:

```bash
gcloud secrets get-iam-policy "${SECRET_ID}" --project="${PROJECT_ID}"
gcloud secrets versions list "${SECRET_ID}" \
  --project="${PROJECT_ID}" --format="table(name,state,createTime)"
gcloud secrets versions access latest --secret="${SECRET_ID}" \
  --project="${PROJECT_ID}" >/dev/null
```

## CMEK and rotation

For CMEK, use a key in every location used by a user-managed secret and grant the Secret Manager service agent the required encrypt/decrypt role. Disabling the key makes protected versions unreadable.

Rotation notifications do not change the credential. A rotation handler must generate a replacement, update the upstream system, add a new secret version, roll consumers, and disable the old version after a rollback window. For databases, consider alternating credentials so both generations can coexist during rollout.

## Audit and destructive operations

Enable Data Access audit logging for reads and inspect `AccessSecretVersion` events without retrieving values. Before disabling, destroying a version, or deleting the container, verify consumers have moved and obtain explicit approval; destruction is irreversible.