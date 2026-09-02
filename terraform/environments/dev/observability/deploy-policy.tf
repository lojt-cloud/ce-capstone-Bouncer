data "aws_caller_identity" "current" {}
data "aws_iam_role" "deploy" {
  name = "ce-capstone-bouncer-deploy"
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  deploy_policy = "${local.project}-${local.environment}-deploy-observability"
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
    sid    = "TFStateReads"
    effect = "Allow"
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