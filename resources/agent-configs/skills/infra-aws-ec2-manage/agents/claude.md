# Claude specifics — infra-aws-ec2-manage

- Load only the EC2 reference needed for the request and preserve IaC ownership.
- Present the expected blast radius and rollback path before any write operation.
- Never expose credentials or commit changes.
