# Junie specifics — infra-aws-iam-manage

- Execute the matching SAD KITTI branch and load only the IAM reference needed.
- Inspect identity and policy effects read-only; require confirmation before privilege increases.
- Do not commit; never display credentials, tokens, or secret values.
