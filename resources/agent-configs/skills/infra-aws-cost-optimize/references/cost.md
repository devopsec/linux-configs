# AWS cost optimization (FinOps)

## Contents
- Review loop
- Cost Explorer CLI
- Budgets and anomaly detection
- Waste finder (read-only)
- Rightsizing and commitments
- Storage / network levers
- Non-prod scheduling
- Terraform/OpenTofu
- Troubleshooting

## Review loop

1. Enforce tags (`Environment`, `Team`, `Service`, `CostCenter`) via Tag Policies/SCP and activate them as cost allocation tags.
2. Enable Cost Explorer + Data Exports (CUR 2.0) to S3.
3. Rank spend by service/account/tag; top 5 drivers get an owner.
4. Rightsize (Compute Optimizer), clean waste, then buy commitments for the steady baseline.
5. Budgets + anomaly alerts; monthly review; track an owner-approved workload unit-cost metric.

## Cost Explorer CLI

```bash
START=$(date -u -d "$(date +%Y-%m-01) -1 month" +%F); END=$(date -u +%Y-%m-01)
aws ce get-cost-and-usage --time-period Start=$START,End=$END --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE
aws ce get-cost-and-usage --time-period Start=$START,End=$END --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=TAG,Key=Team
aws ce get-cost-forecast --time-period Start=$(date -u +%F),End=<yyyy-mm-dd> --metric UNBLENDED_COST --granularity MONTHLY
aws ce get-savings-plans-purchase-recommendation --savings-plans-type COMPUTE_SP \
  --term-in-years ONE_YEAR --payment-option NO_UPFRONT --lookback-period-in-days THIRTY_DAYS
aws ce get-savings-plans-utilization --time-period Start=$START,End=$END
aws ce get-reservation-utilization --time-period Start=$START,End=$END
```

Cost Explorer API calls are billed (~$0.01/request) — don't loop them in cron.

## Budgets and anomaly detection

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws budgets create-budget --account-id "$ACCOUNT_ID" \
  --budget '{"BudgetName":"monthly-total","BudgetLimit":{"Amount":"<amount>","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '[
    {"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},
     "Subscribers":[{"SubscriptionType":"SNS","Address":"<sns-topic-arn>"}]},
    {"Notification":{"NotificationType":"FORECASTED","ComparisonOperator":"GREATER_THAN","Threshold":100,"ThresholdType":"PERCENTAGE"},
     "Subscribers":[{"SubscriptionType":"EMAIL","Address":"<finops-email>"}]}]'
aws ce create-anomaly-monitor --anomaly-monitor '{"MonitorName":"services","MonitorType":"DIMENSIONAL","MonitorDimension":"SERVICE"}'
aws ce create-anomaly-subscription --anomaly-subscription '{"SubscriptionName":"daily","MonitorArnList":["<monitor-arn>"],
  "Subscribers":[{"Type":"SNS","Address":"<sns-topic-arn>"}],"Frequency":"IMMEDIATE",
  "ThresholdExpression":{"Dimensions":{"Key":"ANOMALY_TOTAL_IMPACT_ABSOLUTE","Values":["50"],"MatchOptions":["GREATER_THAN_OR_EQUAL"]}}}'
```

`Threshold` (scalar) on anomaly subscriptions is deprecated — use `ThresholdExpression`. Billing metric alarms (`AWS/Billing EstimatedCharges`) only exist in `us-east-1` and need "Receive Billing Alerts" enabled. Budget actions can apply an SCP/IAM deny automatically — gate with approval.

## Waste finder (read-only; run per region)

```bash
for r in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
  echo "== $r"
  aws ec2 describe-volumes --region "$r" --filters Name=status,Values=available \
    --query 'Volumes[].[VolumeId,Size,CreateTime]' --output text
  aws ec2 describe-addresses --region "$r" --query 'Addresses[?AssociationId==null].[AllocationId,PublicIp]' --output text
  aws ec2 describe-snapshots --region "$r" --owner-ids self \
    --query "Snapshots[?StartTime<='$(date -u -d '-90 days' +%F)'].[SnapshotId,VolumeSize,StartTime]" --output text
  aws elbv2 describe-load-balancers --region "$r" --query 'LoadBalancers[].[LoadBalancerArn]' --output text
done
```

Review the list with the owner, snapshot if in doubt, then delete with `--dry-run` first (EC2 APIs support it). Also check: idle NAT GWs, unused interface endpoints, old AMIs, CloudWatch log groups without retention (`put-retention-policy`), public IPv4 count (Amazon VPC IP Address Manager "Public IP insights").

## Rightsizing and commitments

- `aws compute-optimizer get-ec2-instance-recommendations` / `get-rds-database-recommendations` / `get-lambda-function-recommendations` (opt in first; needs ~14 days of metrics; install CloudWatch agent for memory).
- Order: rightsize → Graviton → Spot for stateless → commit.
- Compute Savings Plans (EC2/Fargate/Lambda, flexible) for baseline; EC2 Instance SPs for higher discount when family is fixed; RDS Reserved Instances where suitable. Compare commitment coverage with measured steady usage and the organization's risk horizon before purchase.

## Storage / network levers

- gp2 → gp3 (≈20 % cheaper, set IOPS/throughput explicitly).
- S3 lifecycle / Intelligent-Tiering (see `infra-aws-s3-manage`); abort incomplete multipart uploads.
- NAT processing: S3/DynamoDB gateway endpoints; keep chatty services in one AZ; cross-AZ traffic costs both directions.
- Internet and cross-region egress can dominate data-heavy workloads; compare transfer paths and regional placement.

## Non-prod scheduling

Use EventBridge Scheduler targets (`arn:aws:scheduler:::aws-sdk:ec2:stopInstances`) or Instance Scheduler on AWS, selecting only resources covered by an owner-approved schedule. Ad-hoc:

```bash
mapfile -t IDS < <(aws ec2 describe-instances --filters Name=tag:Environment,Values=dev Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n')
if ((${#IDS[@]})); then
  aws ec2 stop-instances --instance-ids "${IDS[@]}" --dry-run   # drop --dry-run only after owner review
fi
```

RDS: `aws rds stop-db-instance` (auto-restarts after 7 days). ASGs: scheduled actions to 0.

## Terraform/OpenTofu

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-total"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.finops.arn]
  }
}
resource "aws_ce_anomaly_monitor" "svc" {
  name              = "services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}
```

Use an organization-approved cost-diff tool in CI to show Terraform/OpenTofu changes; use an exact audited version and validate its release artifact.

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| CE empty | enable in Billing console; data lags ~24 h |
| Tag grouping empty | activate cost allocation tags (not retroactive) |
| Budget alert silent | SNS topic policy must allow `budgets.amazonaws.com`; confirm email subscriptions |
| No rightsizing data | Compute Optimizer opt-in + 14 days metrics |
| Billing alarm missing | create in `us-east-1` |
