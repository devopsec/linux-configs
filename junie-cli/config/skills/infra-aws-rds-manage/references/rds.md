# AWS RDS (PostgreSQL first) — provision, params, replicas, backup/restore

Engine-level DBA work (vacuum, indexes, roles, pg_dump) → `infra-postgresql-server-administer`; backup policy/DR drills → `infra-postgresql-backup-manage` and `infra-ops-drPlan-create`.

## Contents
- Versions
- Subnet group + instance
- Credentials (managed secret / IAM auth)
- Parameter groups
- Read replicas / DR
- Snapshots, PITR, Blue/Green
- Monitoring
- Terraform/OpenTofu
- Troubleshooting

## Versions (checked 2026-10-28)

RDS PostgreSQL majors 14–18 are in standard support; latest published minors are 18.6 / 17.11 (August 2026). PostgreSQL 14 standard support ends 2027-02-28, then paid Extended Support applies. PostgreSQL 18.6 is the baseline for new deployments at this check; confirm the exact engine version is available in the target region with:

```bash
aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[].EngineVersion" --output text
```

Pin the major (`--engine-version 18`) and let `--auto-minor-version-upgrade` handle approved minor updates, or pin and test a minor deliberately.

## Subnet group + instance

```bash
aws rds create-db-subnet-group --db-subnet-group-name <env>-db \
  --db-subnet-group-description "<env> data subnets" --subnet-ids <data-subnet-a> <data-subnet-b>

aws rds create-db-instance --db-instance-identifier <env>-<app>-db \
  --engine postgres --engine-version 18 --db-instance-class db.r7g.large \
  --master-username <admin-user> --manage-master-user-password \
  --master-user-secret-kms-key-id alias/<rds-secret-key> \
  --allocated-storage 100 --max-allocated-storage 500 --storage-type gp3 \
  --storage-encrypted --kms-key-id alias/<rds-key> \
  --db-subnet-group-name <env>-db --vpc-security-group-ids <db-sg> --no-publicly-accessible \
  --multi-az --backup-retention-period 14 --preferred-backup-window 03:00-04:00 \
  --preferred-maintenance-window sun:05:00-sun:06:00 --auto-minor-version-upgrade \
  --deletion-protection --copy-tags-to-snapshot \
  --enable-iam-database-authentication \
  --monitoring-interval 60 --monitoring-role-arn arn:aws:iam::<account-id>:role/<rds-monitoring> \
  --database-insights-mode standard --enable-performance-insights \
  --enable-cloudwatch-logs-exports '["postgresql","upgrade"]' \
  --db-parameter-group-name <env>-pg18
aws rds wait db-instance-available --db-instance-identifier <env>-<app>-db
```

- `db.t4g.*` for dev only (burst credits). Multi-AZ DB cluster (2 readable standbys) for lower failover time.
- Require TLS: parameter `rds.force_ssl=1` (default on in PG 15+); clients use `sslmode=verify-full` with the RDS CA bundle.

## Credentials

- `--manage-master-user-password`: RDS stores and rotates the master credential in Secrets Manager. Get the ARN, not the value:
  `aws rds describe-db-instances --db-instance-identifier <id> --query "DBInstances[0].MasterUserSecret.SecretArn" --output text`
  Applications read it at runtime via SDK with a scoped IAM policy — don't print it in shells/CI logs.
- App users: IAM DB auth (`GRANT rds_iam TO <app_user>;`, token via `aws rds generate-db-auth-token`, 15 min lifetime) or per-app secrets. Use RDS Proxy for connection pooling + IAM auth from Lambda.

## Parameter groups

```bash
aws rds create-db-parameter-group --db-parameter-group-name <env>-pg18 \
  --db-parameter-group-family postgres18 --description "<env> PG18"
aws rds modify-db-parameter-group --db-parameter-group-name <env>-pg18 --parameters \
  "ParameterName=shared_buffers,ParameterValue={DBInstanceClassMemory/32768},ApplyMethod=pending-reboot" \
  "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
  "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
  "ParameterName=idle_in_transaction_session_timeout,ParameterValue=60000,ApplyMethod=immediate" \
  "ParameterName=random_page_cost,ParameterValue=1.1,ApplyMethod=immediate"
```

Gotchas: `shared_buffers` is in 8 KB pages (`{DBInstanceClassMemory/32768}` ≈ 25 %); static params need reboot (`aws rds reboot-db-instance`, add `--force-failover` on Multi-AZ to test failover). Default `max_connections` derives from memory — prefer pooling over raising it.

## Read replicas / DR

```bash
aws rds create-db-instance-read-replica --db-instance-identifier <id>-read1 \
  --source-db-instance-identifier <id> --db-instance-class db.r7g.large
# cross-region (encrypted source needs a KMS key in the target region)
aws rds create-db-instance-read-replica --region <dr-region> --db-instance-identifier <id>-dr \
  --source-db-instance-identifier arn:aws:rds:<region>:<account-id>:db:<id> --kms-key-id alias/<dr-key>
# DESTRUCTIVE for replication (breaks link, irreversible): DR failover only
aws rds promote-read-replica --db-instance-identifier <id>-dr
```

Lag: CloudWatch `ReplicaLag` (seconds). Cross-region automated backups: `start-db-instance-automated-backups-replication`.

## Snapshots, PITR, Blue/Green

```bash
aws rds create-db-snapshot --db-instance-identifier <id> --db-snapshot-identifier <id>-pre-<change>-$(date +%Y%m%d)
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier <id> \
  --target-db-instance-identifier <id>-pitr --restore-time <yyyy-mm-ddThh:mm:ssZ> \
  --db-subnet-group-name <env>-db --vpc-security-group-ids <db-sg>
aws rds copy-db-snapshot --source-db-snapshot-identifier <snapshot-arn> \
  --target-db-snapshot-identifier <id>-dr --region <dr-region> --kms-key-id alias/<dr-key>
# Major upgrades with minimal downtime:
aws rds create-blue-green-deployment --blue-green-deployment-name <id>-pg-upgrade \
  --source <db-arn> --target-engine-version 18 --target-db-parameter-group-name <env>-pg18
aws rds switchover-blue-green-deployment --blue-green-deployment-identifier <bgd-id> --switchover-timeout 300
```

Restores always create a new instance — repoint DNS/config; never delete the original until verified. Deleting: `--final-db-snapshot-identifier` required (never `--skip-final-snapshot` on prod; deletion protection must be disabled first — gate it).

## Monitoring

Alarms (SNS → on-call): `CPUUtilization > 80`, `FreeStorageSpace < 10 GiB`, `FreeableMemory`, `DatabaseConnections`, `ReplicaLag`, `ReadLatency/WriteLatency`. Subscribe to RDS events: `aws rds create-event-subscription --source-type db-instance --event-categories failover failure maintenance --sns-topic-arn <topic-arn>`. Export logs to CloudWatch and the approved observability sink.

## Terraform/OpenTofu

```hcl
resource "aws_db_instance" "main" {
  identifier                    = "${var.env}-app-db"
  engine                        = "postgres"
  engine_version                = "18"
  instance_class                = "db.r7g.large"
  allocated_storage             = 100
  max_allocated_storage         = 500
  storage_type                  = "gp3"
  storage_encrypted             = true
  kms_key_id                    = aws_kms_key.rds.arn
  username                      = var.db_admin_user
  manage_master_user_password   = true
  iam_database_authentication_enabled = true
  multi_az                      = true
  db_subnet_group_name          = aws_db_subnet_group.main.name
  vpc_security_group_ids        = [aws_security_group.db.id]
  parameter_group_name          = aws_db_parameter_group.pg18.name
  backup_retention_period       = 14
  deletion_protection           = true
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${var.env}-app-db-final"
  performance_insights_enabled  = true
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  lifecycle { prevent_destroy = true }
}
```

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| Cannot connect | SG from app SG on 5432, NACL, `publicly_accessible=false` + route; DNS of endpoint |
| `no pg_hba.conf entry … SSL off` | client must use TLS (`rds.force_ssl`) |
| Storage full | `max-allocated-storage`; storage autoscaling has a 6 h cooldown |
| Param not applied | `pending-reboot` → reboot in window |
| Connections maxed | RDS Proxy / PgBouncer; fix leaks |
| Upgrade blocked | check `describe-db-engine-versions --query ValidUpgradeTarget`; extensions (PostGIS) versions |
