# Junie specifics — infra-aws-vpc-manage

- Load only the VPC reference and use configured/user-provided CIDRs and ports.
- Inspect routes and effective security policy before suggesting network changes.
- Do not commit; require confirmation before changing public or production connectivity.
