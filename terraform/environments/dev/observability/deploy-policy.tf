data "aws_caller_identity" "current" {}
data "aws_iam_role" "deploy" {
  name = "ce-capstone-bouncer-deploy"
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  aws_region    = "eu-central-1"
  deploy_policy = "${local.project}-${local.environment}-deploy-observability"
  alerts_topic  = "${local.project}-${local.environment}-observability-alerts"
}

data "aws_iam_policy_document" "deploy_observability" {
  # DashboardManage — Get/Put/DeleteDashboards all support resource-level
  # scoping per AWS's CloudWatch service-authorization reference. Dashboard
  # ARNs carry no region segment (arn:aws:cloudwatch::ACCOUNT:dashboard/NAME).
  statement {
    sid    = "DashboardManage"
    effect = "Allow"
    actions = [
      "cloudwatch:GetDashboard",
      "cloudwatch:PutDashboard",
      "cloudwatch:DeleteDashboards",
    ]
    resources = [
      "arn:aws:cloudwatch::${local.account_id}:dashboard/${local.project}-${local.environment}-app-infra",
    ]
  }

  # DashboardListReadOnly — ListDashboards has no resource-level support at
  # all (confirmed via the same reference), unlike its Get/Put/Delete
  # siblings — same shape as the logs:DescribeLogGroups case from CI/CD.
  statement {
    sid       = "DashboardListReadOnly"
    effect    = "Allow"
    actions   = ["cloudwatch:ListDashboards"]
    resources = ["*"]
  }

  # AlarmManage — PutMetricAlarm/DeleteAlarms both require (and support)
  # the "alarm" resource type per AWS's reference. Scoped to the 3 known
  # alarm names.
  statement {
    sid    = "AlarmManage"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
    ]
    resources = [
      "arn:aws:cloudwatch:${local.aws_region}:${local.account_id}:alarm:${local.project}-${local.environment}-high-5xx-rate",
      "arn:aws:cloudwatch:${local.aws_region}:${local.account_id}:alarm:${local.project}-${local.environment}-unhealthy-hosts",
      "arn:aws:cloudwatch:${local.aws_region}:${local.account_id}:alarm:${local.project}-${local.environment}-rds-high-cpu",
    ]
  }
  # AlarmReadOnly — DescribeAlarms has no resource-level scoping support,
  # same shape as DashboardListReadOnly above.
  statement {
    sid       = "AlarmReadOnly"
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }

  statement {
    sid    = "KmsKeyManage"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:GetKeyRotationStatus",
      "kms:ScheduleKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
      "kms:ListAliases",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ListResourceTags",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "KmsKeyPolicyManage"
    effect    = "Allow"
    actions   = ["kms:PutKeyPolicy"]
    resources = [module.observability.sns_alerts_kms_key_arn]
  }

  # SnsTopicManage — same shape as foundation's drift-alerts precedent
  statement {
    sid    = "SnsTopicManage"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
      "sns:Publish",
      "sns:Subscribe",
    ]
    resources = ["arn:aws:sns:${local.aws_region}:${local.account_id}:${local.alerts_topic}"]
  }

  # SnsSubscriptionActions — SNS has no "subscription" IAM resource type at
  # all, confirmed via the same drift-alerts precedent; these three require
  # Resource: "*" unconditionally.
  statement {
    sid    = "SnsSubscriptionActions"
    effect = "Allow"
    actions = [
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:SetSubscriptionAttributes",
    ]
    resources = ["*"]
  }

  # TFStateObject — dev/observability/ prefix only
  statement {
    sid       = "TFStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/observability/*"]
  }

  # TFStateReads — this layer's data.tf reads foundation, compute, and
  # data-tier's state
  statement {
    sid     = "TFStateReads"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/foundation/terraform.tfstate",
      "arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/compute/terraform.tfstate",
      "arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/data-tier/terraform.tfstate",
    ]
  }

  # TFStateList
  statement {
    sid       = "TFStateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dev/observability/*"]
    }
  }

  # PolicySelfManage
  statement {
    sid    = "PolicySelfManage"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:DeletePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:policy/${local.deploy_policy}"]
  }

  # DeployRoleAttach
  statement {
    sid    = "DeployRoleAttach"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [data.aws_iam_role.deploy.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${local.account_id}:policy/${local.deploy_policy}"]
    }
  }
}


resource "aws_iam_policy" "deploy_observability" {
  name        = local.deploy_policy
  description = "Scoped CI deploy-role permissions for the observability layer (terraform/environments/dev/observability)."
  policy      = data.aws_iam_policy_document.deploy_observability.json
}

resource "aws_iam_role_policy_attachment" "deploy_observability" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_observability.arn

}
