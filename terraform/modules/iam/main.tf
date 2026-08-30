# --- EC2 app instance role ---
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name_prefix}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.name_prefix}-app-role"
  }
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "app_cloudwatch" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name_prefix}-app-profile"
  role = aws_iam_role.app.name

  tags = {
    Name = "${var.name_prefix}-app-profile"
  }
}

# --- Foundation-layer slice of the CI/CD deploy role's permissions ---
data "aws_iam_role" "deploy" {
  name = var.deploy_role_name
}

data "aws_iam_policy_document" "deploy_foundation" {
  statement {
    sid       = "NetworkingReadOnly"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid    = "NetworkingNoScopeSupport"
    effect = "Allow"
    actions = [
      "ec2:DeleteVpc", "ec2:ModifyVpcAttribute", "ec2:ModifySubnetAttribute",
      "ec2:ReleaseAddress", "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable", "ec2:ReplaceRoute",
      "ec2:ReplaceRouteTableAssociation"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "NetworkingCreate"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateInternetGateway",
      "ec2:CreateNatGateway", "ec2:AllocateAddress", "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Project"
      values   = [var.project_name]
    }
  }

  statement {
    sid    = "NetworkingManageExisting"
    effect = "Allow"
    actions = [
      "ec2:DeleteSubnet", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway",
      "ec2:DeleteNatGateway", "ec2:AssociateAddress", "ec2:DeleteRouteTable",
      "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable",
      "ec2:DeleteSecurityGroup"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }

  statement {
    sid       = "TagManage"
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["*"]
  }

  statement {
    sid    = "SecurityGroupRuleManage"
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [var.project_name]
    }
  }

  statement {
    sid       = "FlowLogsManage"
    effect    = "Allow"
    actions   = ["ec2:CreateFlowLogs", "ec2:DeleteFlowLogs"]
    resources = ["*"]
  }

  statement {
    sid    = "FlowLogsCloudWatchManage"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:DescribeLogGroups", "logs:ListTagsForResource",
      "logs:TagResource", "logs:UntagResource"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/vpc/${var.project_name}-*"]
  }

  statement {
    sid    = "AppRoleManage"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole",
      "iam:TagRole", "iam:UntagRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile", "iam:UntagInstanceProfile"
    ]
    resources = [
      "arn:aws:iam::${var.account_id}:role/${var.project_name}-*",
      "arn:aws:iam::${var.account_id}:instance-profile/${var.project_name}-*"
    ]
  }

  statement {
    sid    = "DeployPolicyManage"
    effect = "Allow"
    actions = [
      "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:CreatePolicy", "iam:DeletePolicy",
      "iam:CreatePolicyVersion", "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
      "iam:TagPolicy", "iam:UntagPolicy"
    ]
    resources = ["arn:aws:iam::${var.account_id}:policy/${var.project_name}-*"]
  }

  statement {
    sid       = "PassRolesToServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${var.account_id}:role/${var.project_name}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com", "vpc-flow-logs.amazonaws.com"]
    }
  }

  statement {
    sid       = "TerraformStateObjectAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}/dev/foundation/*"]
  }

  statement {
    sid       = "TerraformStateListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.tfstate_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dev/foundation/*"]
    }
  }
}

resource "aws_iam_policy" "deploy_foundation" {
  name   = "${var.name_prefix}-deploy-foundation"
  policy = data.aws_iam_policy_document.deploy_foundation.json
}

resource "aws_iam_role_policy_attachment" "deploy_foundation" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_foundation.arn
}