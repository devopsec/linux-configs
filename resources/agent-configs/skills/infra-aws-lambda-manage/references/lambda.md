# AWS Lambda — functions, triggers, packaging, SAM

## Contents
- Runtimes (2026)
- Create / update / version / alias
- Packaging Python with uv
- Handler patterns
- Event sources
- Function URLs
- Concurrency and cold starts
- SAM
- Troubleshooting

## Runtimes (checked 2026-10-28)

GA runtimes include `python3.14`, `python3.13`, `python3.12`, `nodejs24.x`, `nodejs22.x`, `java21`, and `provided.al2023`. Preview runtimes `python3.15` and `nodejs26.x` are not production defaults as of this check. Amazon Linux 2 runtimes are past the platform EOL date. Node.js 24+ does not support callback-style handlers; use `async`. Check regional support against [AWS Lambda runtime documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html) before deployment.

## Create / update / version / alias

```bash
aws lambda create-function --function-name <fn> \
  --runtime python3.14 --architectures arm64 \
  --handler app.handler --role arn:aws:iam::<account-id>:role/<fn>-exec \
  --zip-file fileb://function.zip --memory-size 256 --timeout 30 \
  --environment 'Variables={STAGE=<env>,LOG_LEVEL=INFO}' \
  --logging-config LogFormat=JSON --tracing-config Mode=Active
aws lambda update-function-code --function-name <fn> --zip-file fileb://function.zip --publish
aws lambda wait function-updated-v2 --function-name <fn>
aws lambda create-alias --function-name <fn> --name live --function-version <n>
# canary: 10 % to new version <n+1>, rest stays on <n>
aws lambda update-alias --function-name <fn> --name live --function-version <n> \
  --routing-config '{"AdditionalVersionWeights":{"<n+1>":0.1}}'
```

Secrets: never in `--environment`. Read from Secrets Manager / SSM Parameter Store at init (or the Parameters and Secrets Lambda Extension); see `sec-secrets-any-manage`.

## Packaging Python with uv

```bash
uv export --frozen --no-dev --no-hashes -o requirements.txt
uv pip install --target build/ -r requirements.txt \
  --python-platform aarch64-manylinux2014 --python-version 3.14 --only-binary=:all:
cp -a src/. build/ && (cd build && zip -qr ../function.zip .)
```

Match `--python-platform` to `--architectures` (`x86_64-manylinux2014` for x86). Large dependencies (>50 MB zipped / 250 MB unzipped) → an ECR container image or a layer.

## Handler patterns

```python
import json, logging, os
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
# create SDK clients at module level (reused across invocations)

def handler(event, context):
    """SQS batch with partial failures (requires ReportBatchItemFailures on the mapping)."""
    failures = []
    for record in event["Records"]:
        try:
            process(json.loads(record["body"]))
        except Exception:  # noqa: BLE001 - report and continue
            logger.exception("failed %s", record["messageId"])
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
```

Make handlers idempotent (at-least-once delivery); use Powertools for AWS Lambda (Python) for logging/idempotency/batch utilities.

## Event sources

```bash
# SQS (queue visibility timeout >= 6 x function timeout)
aws lambda create-event-source-mapping --function-name <fn> \
  --event-source-arn arn:aws:sqs:<region>:<account-id>:<queue> \
  --batch-size 10 --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures
# Streams (DynamoDB/Kinesis): --starting-position LATEST --bisect-batch-on-function-error \
#   --maximum-retry-attempts 3 --destination-config '{"OnFailure":{"Destination":"<sqs-dlq-arn>"}}'

# S3 → Lambda: permission (with source account!) + notification
aws lambda add-permission --function-name <fn> --statement-id s3 \
  --action lambda:InvokeFunction --principal s3.amazonaws.com \
  --source-arn arn:aws:s3:::<bucket> --source-account <account-id>
aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://notif.json

# Schedules: prefer EventBridge Scheduler (time zones, one-off, retries)
aws scheduler create-schedule --name <job> --schedule-expression "cron(0 2 * * ? *)" \
  --schedule-expression-timezone <user-selected-timezone> --flexible-time-window Mode=OFF \
  --target '{"Arn":"<fn-arn>","RoleArn":"<scheduler-role-arn>"}'
```

## Function URLs

- `--auth-type AWS_IAM` by default. `NONE` only for public webhooks — then validate signatures in code, restrict CORS `AllowOrigins`, and set reserved concurrency to cap cost.
- As checked 2026-10-28, `NONE` requires both `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction` resource permissions for `Principal "*"`.

## Concurrency and cold starts

```bash
aws lambda put-function-concurrency --function-name <fn> --reserved-concurrent-executions 50   # also a blast-radius/cost cap
aws lambda put-provisioned-concurrency-config --function-name <fn> --qualifier live --provisioned-concurrent-executions 5
aws lambda update-function-configuration --function-name <fn> --snap-start ApplyOn=PublishedVersions  # Java, Python 3.12+, .NET 8+
```

Tips: arm64, small packages, lazy-import heavy modules, VPC only when needed (Hyperplane ENIs made VPC cold starts small but NAT is still needed for egress).

## SAM

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Globals:
  Function:
    Runtime: python3.14
    Architectures: [arm64]
    Timeout: 30
    LoggingConfig: { LogFormat: JSON }
Parameters:
  Stage: { Type: String, AllowedValues: [dev, staging, prod] }
Resources:
  QueueFn:
    Type: AWS::Serverless::Function
    Properties:
      Handler: app.handler
      CodeUri: build/
      AutoPublishAlias: live
      DeploymentPreference: { Type: Canary10Percent5Minutes }
      Events:
        Q:
          Type: SQS
          Properties: { Queue: !GetAtt Queue.Arn, BatchSize: 10, FunctionResponseTypes: [ReportBatchItemFailures] }
  Queue:
    Type: AWS::SQS::Queue
    Properties: { VisibilityTimeout: 180 }
```

```bash
sam validate --lint && sam build && sam local invoke QueueFn -e events/sqs.json
sam deploy --stack-name <app>-<stage> --parameter-overrides Stage=<stage> --confirm-changeset
sam logs --stack-name <app>-<stage> --name QueueFn --tail
```

Use AWS SAM CLI `1.170.0` (checked 2026-10-28) from an approved package source; do not install through shell-piped downloads.

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| Timeout | raise timeout; check NAT/VPC endpoints for downstream calls |
| OOM / slow | raise memory (CPU scales with memory); Lambda Power Tuning |
| SQS reprocessing | visibility timeout ≥ 6× function timeout; partial batch responses |
| Mapping disabled | fix errors, then `update-event-source-mapping --enabled` |
| `Runtime.ImportModuleError` | wrong arch/platform wheels; rebuild with matching `--python-platform` |
| Function URL 403 | auth type vs resource policy; both invoke permissions for `NONE` |
