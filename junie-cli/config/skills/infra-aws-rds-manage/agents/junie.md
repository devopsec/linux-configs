# Junie specifics — infra-aws-rds-manage

- Follow the RDS SAD KITTI branch and load only the database reference needed.
- Preserve backups and confirm account, region, downtime, and recovery plan before changes.
- Do not commit; redact database endpoints and all credential material.
