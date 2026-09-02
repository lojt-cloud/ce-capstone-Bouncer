# ADR 000X: Customer-managed KMS key for the observability alerts SNS topic

## Status
Accepted

## Context
The observability alerts SNS topic needs encryption at rest. The default
choice, the AWS-managed key `alias/aws/sns`, is free and requires no
management — but its key policy is fixed by AWS and does not grant
`cloudwatch.amazonaws.com` permission to encrypt messages on publish.
Every CloudWatch alarm action against an `alias/aws/sns`-encrypted topic
fails silently: the alarm state changes correctly, but
`describe-alarm-history` shows the SNS publish itself failing with
"CloudWatch Alarms does not have authorization to access the SNS topic
encryption key." No error surfaces anywhere else — alarms simply never
notify.

## Decision
Use a customer-managed KMS key (`aws_kms_key.sns_alerts`) for the topic
instead, with an explicit key policy granting `cloudwatch.amazonaws.com`
`kms:Decrypt` and `kms:GenerateDataKey*`, alongside the standard
account-root full-access statement. The CI deploy role's IAM policy
(`deploy_observability`) was extended with a `KmsKeyManage` statement to
create and manage this key; `kms:CreateKey` requires `Resource = "*"`
since the key ARN doesn't exist before creation, unlike the SNS/CloudWatch
statements which scope to deterministic ARNs.

## Consequences
- $1/month recurring cost for the CMK (see COSTS.md), versus $0 for the
  AWS-managed key.
- The deploy IAM policy carries one unscoped (`Resource = "*"`) KMS
  statement, a deliberate least-privilege trade-off, not an oversight —
  see COSTS.md/SECURITY.md note.
- Alarm-to-SNS delivery is now verified working (see RUNBOOK.md test
  procedure).