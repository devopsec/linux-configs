# AWS Secrets Manager

## Create, update, and read safely

Use customer-managed KMS keys where policy requires independent key control. Pass payloads through a mode-restricted file, not a literal command-line argument, and remove temporary plaintext after use.

```bash
aws secretsmanager create-secret --name "${SECRET_NAME}" \
  --kms-key-id "${KMS_KEY_ARN}" --secret-string "file://${SECRET_FILE}"
aws secretsmanager put-secret-value --secret-id "${SECRET_ID_OR_ARN}" \
  --secret-string "file://${SECRET_FILE}"
aws secretsmanager describe-secret --secret-id "${SECRET_ID_OR_ARN}"
aws secretsmanager list-secret-version-ids --secret-id "${SECRET_ID_OR_ARN}"
```

Use `get-secret-value` only when the consumer needs the payload; never print the output during a verification task. Scope `secretsmanager:GetSecretValue` to the exact secret ARN and grant `kms:Decrypt` only for the relevant key. Use workload IAM roles, not static access keys.

## Rotation and workloads

Prefer an AWS-provided rotation template for supported databases. Validate each rotation stage (`createSecret`, `setSecret`, `testSecret`, `finishSecret`) and confirm the pending credential works before promotion. Check application cache TTLs and consider alternating users for zero-downtime database rotation.

ECS and SDK consumers should reference the secret ARN and appropriate JSON key without embedding the value in task definitions or logs. Cross-account access requires a resource policy and key policy that agree on the trusted principal.

## Deletion and response

Deletion schedules a recovery window; force deletion can remove that protection. Do not delete or force-delete without explicit approval and a verified recovery plan. Treat a value printed, committed, or exposed in a build log as compromised and coordinate rotation across consumers.