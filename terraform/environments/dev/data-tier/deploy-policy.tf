data "aws_caller_identity" "current" {}

data "aws_iam_role" "deploy" {
  name = "ce-capstone-bouncer-deploy"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  aws_region = "eu-central-1"

  db_secret_policy    = "${local.project}-${local.environment}-database-secret-read"
  cache_secret_policy = "${local.project}-${local.environment}-cache-secret-read"
  deploy_policy       = "${local.project}-${local.environment}-deploy-data-tier"
}

data "aws_iam_policy_document" "deploy_data_tier" {

  # RDSInstanceManage — Create/Delete/Modify support resource-level scoping
  statement {
    sid    = "RDSInstanceManage"
    effect = "Allow"
    actions = [
      "rds:CreateDBInstance",
      "rds:DeleteDBInstance",
      "rds:ModifyDBInstance",
    ]
    resources = ["arn:aws:rds:${local.aws_region}:${local.account_id}:db:${local.project}-${local.environment}-db"]
  }

  # RDSSubnetGroupManage
  statement {
    sid    = "RDSSubnetGroupManage"
    effect = "Allow"
    actions = [
      "rds:CreateDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
    ]
    resources = ["arn:aws:rds:${local.aws_region}:${local.account_id}:subgrp:${local.project}-${local.environment}-db"]
  }

  # RDSTagManage
  statement {
    sid    = "RDSTagManage"
    effect = "Allow"
    actions = [
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
      "rds:ListTagsForResource",
    ]
    resources = [
      "arn:aws:rds:${local.aws_region}:${local.account_id}:db:${local.project}-${local.environment}-db",
      "arn:aws:rds:${local.aws_region}:${local.account_id}:subgrp:${local.project}-${local.environment}-db",
    ]
  }

  # RDSReadOnly — Describe* has no resource-level support, confirmed via
  # AWS's RDS service-authorization reference
  statement {
    sid    = "RDSReadOnly"
    effect = "Allow"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBSubnetGroups",
    ]
    resources = ["*"]
  }

  # ElastiCacheReplicationGroupManage
  statement {
    sid    = "ElastiCacheReplicationGroupManage"
    effect = "Allow"
    actions = [
      "elasticache:CreateReplicationGroup",
      "elasticache:DeleteReplicationGroup",
      "elasticache:ModifyReplicationGroup",
    ]
    resources = ["arn:aws:elasticache:${local.aws_region}:${local.account_id}:replicationgroup:${local.project}-${local.environment}-cache"]
  }

  # ElastiCacheSubnetGroupManage
  statement {
    sid    = "ElastiCacheSubnetGroupManage"
    effect = "Allow"
    actions = [
      "elasticache:CreateCacheSubnetGroup",
      "elasticache:DeleteCacheSubnetGroup",
    ]
    resources = ["arn:aws:elasticache:${local.aws_region}:${local.account_id}:subnetgroup:${local.project}-${local.environment}-cache"]
  }

  # ElastiCacheTagManage
  statement {
    sid    = "ElastiCacheTagManage"
    effect = "Allow"
    actions = [
      "elasticache:AddTagsToResource",
      "elasticache:RemoveTagsFromResource",
      "elasticache:ListTagsForResource",
    ]
    resources = [
      "arn:aws:elasticache:${local.aws_region}:${local.account_id}:replicationgroup:${local.project}-${local.environment}-cache",
      "arn:aws:elasticache:${local.aws_region}:${local.account_id}:subnetgroup:${local.project}-${local.environment}-cache",
    ]
  }

  # ElastiCacheReadOnly — Describe* has no resource-level support, confirmed
  # via AWS's ElastiCache service-authorization reference
  statement {
    sid    = "ElastiCacheReadOnly"
    effect = "Allow"
    actions = [
      "elasticache:DescribeReplicationGroups",
      "elasticache:DescribeCacheClusters",
      "elasticache:DescribeCacheSubnetGroups",
    ]
    resources = ["*"]
  }

  # SecretsManage — db + cache credential secrets. Scoped by name pattern
  # (trailing -*) since Secrets Manager appends a random 6-char suffix to
  # the real ARN that isn't known before creation; AWS evaluates the
  # requested name against this pattern even pre-creation (confirmed via
  # AWS's Secrets Manager service-authorization reference).
  statement {
    sid    = "SecretsManage"
    effect = "Allow"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = [
      "arn:aws:secretsmanager:${local.aws_region}:${local.account_id}:secret:${local.project}-${local.environment}-db-credentials-*",
      "arn:aws:secretsmanager:${local.aws_region}:${local.account_id}:secret:${local.project}-${local.environment}-cache-credentials-*",
    ]
  }

  # PolicySelfManage — the two secret-read policies (created by the shared
  # database/cache modules) plus this policy's own self-management
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
    resources = [
      "arn:aws:iam::${local.account_id}:policy/${local.db_secret_policy}",
      "arn:aws:iam::${local.account_id}:policy/${local.cache_secret_policy}",
      "arn:aws:iam::${local.account_id}:policy/${local.deploy_policy}",
    ]
  }

  # AppRoleAttach — attach/detach the two secret-read policies to
  # Foundation's shared app role only
  statement {
    sid    = "AppRoleAttach"
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [data.terraform_remote_state.foundation.outputs.app_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::${local.account_id}:policy/${local.db_secret_policy}",
        "arn:aws:iam::${local.account_id}:policy/${local.cache_secret_policy}",
      ]
    }
  }

  # DeployRoleAttach — attach/detach this policy to the deploy role only
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

  # TFStateObject — dev/data-tier/ prefix only
  statement {
    sid       = "TFStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/data-tier/*"]
  }

  # TFStateFoundationRead — read-only, single-object access to foundation's
  # state (needed by this layer's terraform_remote_state.foundation read
  # for private_subnet_ids/db_security_group_id/cache_security_group_id/
  # app_role_arn). Same pattern as compute's TFStateObjectDataTierRead.
  statement {
    sid       = "TFStateFoundationRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/foundation/terraform.tfstate"]
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
      values   = ["dev/data-tier/*"]
    }
  }
}

resource "aws_iam_policy" "deploy_data_tier" {
  name        = local.deploy_policy
  description = "Scoped CI deploy-role permissions for the data-tier layer (terraform/environments/dev/data-tier)."
  policy      = data.aws_iam_policy_document.deploy_data_tier.json
}

resource "aws_iam_role_policy_attachment" "deploy_data_tier" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_data_tier.arn
}
