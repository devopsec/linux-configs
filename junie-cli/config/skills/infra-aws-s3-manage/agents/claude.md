# Claude specifics — infra-aws-s3-manage

- Load only the S3 reference and check bucket policy with identity and KMS policy.
- Require review before irreversible retention or bulk-delete actions.
- Never disclose object data or commit changes.
