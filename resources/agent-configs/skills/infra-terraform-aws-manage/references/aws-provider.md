# Terraform AWS provider

Use Terraform `1.17.0` and `hashicorp/aws` `6.70.0` as checked 2026-10-28. Commit `.terraform.lock.hcl`; review provider upgrades separately and inspect the full plan for replacement or IAM changes.

## Authentication and provider

Use AWS SSO/role-based credentials locally and OIDC federation in CI. Never write access keys in HCL or variable files. Assume a dedicated deployment role and use aliases only for intentionally multi-account/region stacks.

```hcl
terraform {
  required_version = "= 1.17.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
  }
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn     = var.deploy_role_arn
    session_name = "terraform"
  }
  default_tags {
    tags = { ManagedBy = "terraform", Environment = var.environment }
  }
}
```

## S3 backend

Bootstrap the state bucket separately. Enable versioning, encryption, public-access blocking, and native lockfile support; scope state access to the deploy role and state bucket. Use partial backend configuration so account/bucket/prefix are supplied by the environment rather than committed as live values.

```hcl
terraform {
  backend "s3" {
    use_lockfile = true
  }
}
```

S3 backend locking with `use_lockfile` requires Terraform `1.10+`; the Terraform CLI is pinned here at `1.17.0`. Keep the state bucket recovery procedure and lock ownership documented.

## VPC and security groups

Use separate public/private subnet inputs, enable flow logs when useful, and place private workloads behind deliberate egress. Keep CIDRs and availability zones as user inputs. Use standalone security-group rule resources with one ownership model; do not mix inline rules and standalone rules on the same group.

For multi-AZ VPCs, prefer a maintained registry module pinned to an exact reviewed version. If implementing the VPC directly, use stable `for_each` keys rather than `count` indices so changing the AZ list does not shift resource addresses.

```hcl
resource "aws_security_group" "service" {
  name   = "${var.name_prefix}-service"
  vpc_id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "service" {
  for_each          = var.allowed_ingress
  security_group_id = aws_security_group.service.id
  cidr_ipv4         = each.value.cidr
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
}
```

For administrative access, prefer Systems Manager Session Manager or a controlled bastion rather than a public SSH rule. Do not put `0.0.0.0/0` on sensitive ports.

## EC2 and RDS

Require IMDSv2 (`http_tokens = "required"`), encrypted EBS, least-privilege instance profiles, and a controlled AMI update policy. Pin exact AMI IDs for reproducible production plans or roll images deliberately.

```hcl
resource "aws_instance" "workload" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.instance_profile_name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }
}
```

For RDS, keep the database private, use encryption, backups, deletion protection, Multi-AZ according to the availability objective, and managed master credentials. Avoid database passwords in Terraform state; use Secrets Manager and provider-supported write-only fields where available.

```hcl
resource "aws_db_instance" "postgres" {
  identifier                   = var.db_identifier
  engine                       = "postgres"
  engine_version               = var.postgres_version
  instance_class               = var.db_instance_class
  allocated_storage            = var.allocated_storage_gb
  storage_encrypted            = true
  db_subnet_group_name         = var.db_subnet_group_name
  vpc_security_group_ids       = var.db_security_group_ids
  manage_master_user_password  = true
  multi_az                     = var.multi_az
  backup_retention_period      = var.backup_retention_days
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = var.final_snapshot_identifier
  publicly_accessible          = false
}
```

Master credentials managed by RDS are stored in Secrets Manager and avoid Terraform state. Use IAM DB authentication where supported; rotate credentials and test restores under the owning database policy.

## Review checklist

- Verify account and region before planning; inspect provider aliases and role assumption.
- Confirm security group ingress and egress are narrow and intentionally owned.
- Check encryption, backup retention, final snapshot, deletion protection, and public accessibility.
- Run `terraform fmt -check`, `terraform validate`, and `terraform plan -out=tfplan`; obtain approval before apply.

## References

- [AWS provider registry](https://registry.terraform.io/providers/hashicorp/aws/6.70.0/docs) — published 2026-10-22; checked 2026-10-28.
- [AWS provider authentication](https://registry.terraform.io/providers/hashicorp/aws/6.70.0/docs#authentication) — checked 2026-10-28.