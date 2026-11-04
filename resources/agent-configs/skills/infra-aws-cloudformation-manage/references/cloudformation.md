# AWS CloudFormation — templates, change sets, drift, nested stacks

Use Terraform/OpenTofu by default. Choose CloudFormation when AWS-native integrations or existing stack ownership require it (for example, SAM applications, StackSets, Control Tower, Service Catalog, or third-party templates); never manage one resource from multiple IaC systems.

## Contents
- Template skeleton
- Lint / validate
- Deploy via change sets
- Drift
- Nested stacks / packaging
- Protection: termination, stack policy, DeletionPolicy
- Intrinsic functions cheat sheet
- Debugging
- Troubleshooting

## Template skeleton

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: <app> web tier
Parameters:
  Environment: { Type: String, AllowedValues: [dev, staging, prod] }
  VpcId: { Type: 'AWS::EC2::VPC::Id' }
  SubnetIds: { Type: 'List<AWS::EC2::Subnet::Id>' }
  AmiId: { Type: 'AWS::EC2::Image::Id', Description: Approved immutable AMI ID for this deployment }
  PublicSourceCidr: { Type: String, Description: User-approved CIDR for public HTTPS access }
  DbSecretArn: { Type: String, Description: Secrets Manager ARN (never pass secret values as parameters) }
Conditions:
  IsProd: !Equals [!Ref Environment, prod]
Resources:
  WebSG:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: !Sub '${Environment}-web'
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - { IpProtocol: tcp, FromPort: 443, ToPort: 443, CidrIp: !Ref PublicSourceCidr }
  LaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateData:
        ImageId: !Ref AmiId
        InstanceType: !If [IsProd, c7i.large, t3.small]
        MetadataOptions: { HttpTokens: required }
        SecurityGroupIds: [!Ref WebSG]
  Asg:
    Type: AWS::AutoScaling::AutoScalingGroup
    CreationPolicy: { ResourceSignal: { Count: 1, Timeout: PT15M } }
    UpdatePolicy:
      AutoScalingRollingUpdate: { MinInstancesInService: !If [IsProd, 2, 0], MaxBatchSize: 1, PauseTime: PT10M, WaitOnResourceSignals: true }
    Properties:
      LaunchTemplate: { LaunchTemplateId: !Ref LaunchTemplate, Version: !GetAtt LaunchTemplate.LatestVersionNumber }
      MinSize: !If [IsProd, 2, 1]
      MaxSize: !If [IsProd, 10, 2]
      VPCZoneIdentifier: !Ref SubnetIds
  Data:
    Type: AWS::S3::Bucket
    DeletionPolicy: Retain
    UpdateReplacePolicy: Retain
Outputs:
  WebSGId:
    Value: !Ref WebSG
    Export: { Name: !Sub '${AWS::StackName}-WebSGId' }
```

Secrets: use dynamic references (`'{{resolve:secretsmanager:<secret-arn>:SecretString:<key>}}'`, `{{resolve:ssm:/path}}`) or `ManageMasterUserPassword: true` for RDS. Never `NoEcho` parameters with defaults.

## Lint / validate

```bash
uv tool install cfn-lint==1.58.0  # exact version checked 2026-10-28
cfn-lint template.yaml
aws cloudformation validate-template --template-body file://template.yaml
# Optional policy scanning: use the exact version locked by the organization.
```

Run `cfn-lint` in CI alongside the organization's other linters.

## Deploy via change sets

```bash
aws cloudformation deploy --stack-name <env>-web --template-file template.yaml \
  --parameter-overrides Environment=<env> VpcId=<vpc-id> SubnetIds=<subnet-a>,<subnet-b> \
  --capabilities CAPABILITY_NAMED_IAM --tags Environment=<env> \
  --no-execute-changeset                                  # creates change set only
aws cloudformation describe-change-set --stack-name <env>-web --change-set-name <name> \
  --query 'Changes[].ResourceChange.{A:Action,R:LogicalResourceId,T:ResourceType,Repl:Replacement}' --output table
aws cloudformation execute-change-set --stack-name <env>-web --change-set-name <name>   # after review
aws cloudformation wait stack-update-complete --stack-name <env>-web
```

Review every `Replacement: True` (data loss risk for DBs/buckets). New stacks: add `--enable-termination-protection` via `update-termination-protection` after create. Multi-account/region: StackSets with service-managed permissions.

## Drift

```bash
ID=$(aws cloudformation detect-stack-drift --stack-name <stack> --query StackDriftDetectionId --output text)
aws cloudformation describe-stack-drift-detection-status --stack-drift-detection-id "$ID"
aws cloudformation describe-stack-resource-drifts --stack-name <stack> \
  --stack-resource-drift-status-filters MODIFIED DELETED --output table
```

Fix by updating the template (preferred) or reverting the manual change; for adopting existing resources use resource import (`create-change-set --change-set-type IMPORT`). Check current regional AWS documentation before depending on newer drift-aware change-set behavior.

## Nested stacks / packaging

```bash
aws cloudformation package --template-file parent.yaml --s3-bucket <artifact-bucket> --output-template-file packaged.yaml
aws cloudformation deploy --template-file packaged.yaml --stack-name <app> --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
```

Parent uses `AWS::CloudFormation::Stack` with local `TemplateURL: ./network.yaml` (package rewrites to S3) and passes outputs via `!GetAtt Child.Outputs.X`. Prefer nested stacks for composition, exports/`!ImportValue` only for stable cross-stack contracts (an exported value can't change while imported).

## Protection

- `update-termination-protection --enable-termination-protection`.
- Stack policy denying `Update:Replace`/`Update:Delete` on `LogicalResourceId/Database`.
- `DeletionPolicy: Snapshot|Retain` + `UpdateReplacePolicy` on stateful resources.
- Delete stack (DESTRUCTIVE): confirm stack name + env with the user, check `Retain` resources, then `delete-stack` + `wait stack-delete-complete`.

## Intrinsic functions cheat sheet

`!Ref`, `!GetAtt R.Attr`, `!Sub '${AWS::StackName}-x'`, `!Sub ['arn:aws:s3:::${B}/*', {B: !Ref Bucket}]`, `!Join ['-', [a, b]]`, `!Select [0, !GetAZs '']`, `!Split [',', !Ref Csv]`, `!If [Cond, a, b]`, `!Equals`, `!ImportValue`, `!Cidr [!GetAtt VPC.CidrBlock, 6, 8]`, `!FindInMap`. `Fn::ForEach` needs `Transform: AWS::LanguageExtensions`.

## Debugging

```bash
aws cloudformation describe-stack-events --stack-name <stack> \
  --query "StackEvents[?contains(ResourceStatus,'FAILED')].[Timestamp,LogicalResourceId,ResourceStatusReason]" --output table
aws cloudformation continue-update-rollback --stack-name <stack> --resources-to-skip <LogicalId>
aws cloudformation cancel-update-stack --stack-name <stack>
aws cloudformation get-template --stack-name <stack> --template-stage Processed --query TemplateBody --output text
```

Only in an isolated development stack, and after explicit confirmation, use `--disable-rollback` to inspect failed resources; restore or delete the stack after review.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Requires capabilities` | `CAPABILITY_IAM`/`CAPABILITY_NAMED_IAM`/`CAPABILITY_AUTO_EXPAND` |
| UPDATE_ROLLBACK_FAILED | `continue-update-rollback --resources-to-skip` |
| Circular dependency | split SG ingress into `AWS::EC2::SecurityGroupIngress`; remove `DependsOn` loops |
| Export in use | change importer first; use stack-name-prefixed exports |
| Template >51,200 bytes | `--s3-bucket` / `package` (S3 limit 1 MB) |
| Delete fails | non-empty bucket, SG referenced outside stack, ENIs from Lambda |
