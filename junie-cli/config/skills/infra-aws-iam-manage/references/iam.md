# AWS IAM — roles, policies, federation, auditing

Principles: roles + temporary credentials only (no long-lived access keys for workloads/CI); least privilege; scope `Resource` and add `Condition`s; validate with Access Analyzer before apply.

## Contents
- Policy skeleton
- Service roles + instance profiles
- Cross-account assume-role
- Federation: OIDC identity provider → AWS
- Permission boundaries and SCPs
- Auditing
- Troubleshooting

## Policy skeleton

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {"Sid": "RW", "Effect": "Allow",
     "Action": ["s3:GetObject", "s3:PutObject"],
     "Resource": "arn:aws:s3:::<bucket>/<prefix>/*"},
    {"Sid": "List", "Effect": "Allow", "Action": "s3:ListBucket",
     "Resource": "arn:aws:s3:::<bucket>",
     "Condition": {"StringLike": {"s3:prefix": "<prefix>/*"}}}
  ]
}
```

Evaluation: explicit Deny > Allow; effective = identity ∩ boundary ∩ SCP ∩ session policy (+ resource policy for same-account Allow). Validate: `aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document file://p.json`.

## Service roles + instance profiles

```bash
aws iam create-role --role-name <app>-ec2 \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam put-role-policy --role-name <app>-ec2 --policy-name app-s3 --policy-document file://app-s3.json
aws iam attach-role-policy --role-name <app>-ec2 --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name <app>-ec2
aws iam add-role-to-instance-profile --instance-profile-name <app>-ec2 --role-name <app>-ec2
```

Lambda: principal `lambda.amazonaws.com` + `service-role/AWSLambdaBasicExecutionRole` (add `AWSLambdaVPCAccessExecutionRole` only when VPC-attached). Add `aws:SourceAccount`/`aws:SourceArn` conditions to service trust policies (confused-deputy protection).

## Cross-account assume-role

Trust policy in target account (`<target-account-id>`):

```json
{"Effect": "Allow",
 "Principal": {"AWS": "arn:aws:iam::<source-account-id>:role/<caller-role>"},
 "Action": "sts:AssumeRole",
 "Condition": {"StringEquals": {"sts:ExternalId": "${EXTERNAL_ID}"}}}
```

Use a specific role ARN, not `:root`, unless you intentionally delegate to the whole account. ExternalId is for third parties; keep it in AWS Secrets Manager or an approved secret store, not in docs.

Prefer named profiles over exporting keys (writes the CLI config file, no secrets stored):

```bash
aws configure set role_arn arn:aws:iam::<target-account-id>:role/<role> --profile target
aws configure set source_profile default --profile target
aws configure set external_id "${EXTERNAL_ID}" --profile target
```

`aws sts get-caller-identity --profile target` to verify. Humans: IAM Identity Center (`aws configure sso`, `aws sso login`) instead of IAM users.

## Federation (no stored keys in CI)

### GitHub Actions → AWS

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
```

AWS no longer validates the thumbprint for this IdP (trusted root CAs are used); `thumbprint_list` can be omitted in current Terraform AWS provider. Trust condition: `token.actions.githubusercontent.com:aud = sts.amazonaws.com` and pin `sub` to `repo:<org>/<repo>:ref:refs/heads/main` or `repo:<org>/<repo>:environment:<env>` — never `repo:<org>/*`.

```yaml
permissions: { id-token: write, contents: read }
steps:
  - uses: aws-actions/configure-aws-credentials@v6.3.0   # version checked 2026-10-28; pin its audited commit SHA in production
    with:
      role-to-assume: arn:aws:iam::<account-id>:role/<gha-deploy>
      aws-region: <region>
```

## Permission boundaries and SCPs

- Boundary: managed policy that caps what delegated admins/roles can grant. Include a Deny on `iam:DeleteRolePermissionsBoundary`/`iam:PutRolePermissionsBoundary` and require the boundary on `iam:CreateRole` (`Condition: StringEquals iam:PermissionsBoundary <boundary-arn>`).
- SCP guardrails (Organizations): deny root usage (`aws:PrincipalArn` like `arn:aws:iam::*:root`), require IMDSv2 (`ec2:RunInstances` with `ec2:MetadataHttpTokens != required`), restrict regions (`aws:RequestedRegion` NotIn list, exempt an admin role), deny disabling CloudTrail/GuardDuty/Config. Consider Resource Control Policies (RCPs) for data-perimeter rules.

## Auditing

```bash
aws accessanalyzer create-analyzer --analyzer-name account --type ACCOUNT
aws accessanalyzer create-analyzer --analyzer-name unused --type ACCOUNT_UNUSED_ACCESS \
  --configuration '{"unusedAccess":{"unusedAccessAge":90}}'
aws accessanalyzer list-findings-v2 --analyzer-arn <analyzer-arn>

aws iam generate-credential-report
aws iam get-credential-report --query Content --output text > "${TMPDIR:-/tmp}/credential-report.b64"
# Content is base64-encoded CSV: decode locally with your base64 tool; check password_enabled/mfa_active/access_key_*_last_rotated

aws iam generate-service-last-accessed-details --arn <role-arn>      # → JobId
aws iam get-service-last-accessed-details --job-id <job-id>
aws iam simulate-principal-policy --policy-source-arn <role-arn> \
  --action-names s3:GetObject --resource-arns arn:aws:s3:::<bucket>/<key>
aws iam list-attached-role-policies --role-name <role>; aws iam list-role-policies --role-name <role>
```

Feed CloudTrail into the organization-approved audit sink; generate least-privilege policies from activity with `accessanalyzer start-policy-generation`.

Provider baseline: `hashicorp/aws` `6.70.0` (checked 2026-10-28); commit the exact tested provider selection in the IaC lock file.

## Troubleshooting

| Problem | Fix |
|---|---|
| AccessDenied | decode: `aws sts decode-authorization-message --encoded-message <msg>`; simulate; check SCP/boundary/resource policy |
| Role cannot be assumed | trust policy principal, ExternalId, `sts:TagSession` if tags passed |
| OIDC fails | `aud`/`sub` mismatch — print claims of the token (do not log the token itself) |
| Boundary blocks action | effective = identity ∩ boundary; add action to boundary |
| SLR creation fails | SCP blocks `iam:CreateServiceLinkedRole` — add exception |
| MFA not enforced | `aws:MultiFactorAuthPresent` condition (humans only) |
