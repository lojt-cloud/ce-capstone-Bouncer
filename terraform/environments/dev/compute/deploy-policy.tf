data "aws_caller_identity" "current" {}

data "aws_iam_role" "deploy" {
  name = "ce-capstone-bouncer-deploy"
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  asg_name           = "${local.project}-${local.environment}-app-asg"
  alb_name           = "${local.project}-${local.environment}-alb"
  artifact_bucket    = module.compute.app_artifact_bucket_name
  log_group_name     = module.compute.app_log_group_name
  waf_log_group_name = "aws-waf-logs-${local.project}-${local.environment}"

  artifact_policy   = "${local.project}-${local.environment}-compute-app-artifact-read"
  deploy_policy     = "${local.project}-${local.environment}-deploy-compute"
  deploy_policy_ext = "${local.project}-${local.environment}-deploy-compute-ext"

  tag_layer = "compute"
}

# Sids are deliberately omitted from every statement below (not effect ="Deny" or
# security-relevant) — this policy sits close to IAM's 6,144-char managed-policy
# quota (a hard limit, not adjustable) once the S3 bucket's full set of read
# permissions is included. Each statement is labeled by comment instead; the label
# still shows up here and in `terraform plan` diffs, just not in the AWS console.
#
# BucketManage plus the ACM and Route53 permissions live in a SEPARATE managed
# policy (deploy_compute_ext, below) rather than as statements here — adding ACM
# and Route53 alone to this policy pushed its rendered JSON to 6,135/6,144 bytes
# (a real CreatePolicyVersion 409 LimitExceeded on 2026-09-02, not a guess) —
# technically under quota but with zero margin for the next addition. Moving
# BucketManage out too gives both policies real headroom instead of a razor-thin
# fit. AWS raised the managed-policies-per-role quota to 20 by default in a 2026
# update, so a second policy attached to the same deploy role costs nothing.

data "aws_iam_policy_document" "deploy_compute" {

  # ReadOnly — Describe*/List* actions with no resource-level IAM support
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribePolicies",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeInstanceRefreshes",
      "autoscaling:DescribeTags",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  # LTCreate — launch template create (RequestTag)
  statement {
    effect    = "Allow"
    actions   = ["ec2:CreateLaunchTemplate"]
    resources = ["arn:aws:ec2:${local.aws_region}:${local.account_id}:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # LTManage — launch template manage existing (ResourceTag)
  statement {
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["arn:aws:ec2:${local.aws_region}:${local.account_id}:launch-template/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # ASGCreate
  statement {
    effect    = "Allow"
    actions   = ["autoscaling:CreateAutoScalingGroup"]
    resources = ["arn:aws:autoscaling:${local.aws_region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # ASGManage
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:PutScalingPolicy",
      "autoscaling:DeletePolicy",
      "autoscaling:AttachLoadBalancerTargetGroups",
      "autoscaling:DetachLoadBalancerTargetGroups",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags",
      "autoscaling:StartInstanceRefresh",
    ]
    resources = ["arn:aws:autoscaling:${local.aws_region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${local.asg_name}"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # ELBv2Create
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:loadbalancer/app/${local.alb_name}/*",
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:listener/app/${local.alb_name}/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # ELBv2Manage — manage existing (ResourceTag)
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:loadbalancer/app/${local.alb_name}/*",
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:listener/app/${local.alb_name}/*/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Layer"
      values   = [local.tag_layer]
    }
  }

  # ELBv2SetWebACL — split out of ELBv2Manage above, 2026-09-02. Two failed
  # applies confirmed elasticloadbalancing:SetWebACL genuinely does not
  # honor the aws:ResourceTag condition (identical 403 immediately after a
  # confirmed-applied policy update, ruling out propagation lag) --
  # corroborated by AWS's own production aws-load-balancer-controller IAM
  # policy (github.com/kubernetes-sigs/aws-load-balancer-controller),
  # which grants this exact action with NO condition at all, unlike its
  # sibling actions in the same policy. Scoped to this ALB's ARN, not "*"
  # -- the earlier 403 named that specific ARN, confirming ARN-level
  # scoping does work here, just not the tag condition. Case 17 of this
  # project's "looks scopeable, isn't" pattern (a hidden dependency on a
  # different service's action, same shape as ec2:RunInstances/CreateTags
  # and route53:GetHostedZone) -- with the added nuance that the action
  # supports resource ARNs but not this particular condition key.
  statement {
    effect    = "Allow"
    actions   = ["elasticloadbalancing:SetWebACL"]
    resources = ["arn:aws:elasticloadbalancing:${local.aws_region}:${local.account_id}:loadbalancer/app/${local.alb_name}/*"]
  }

  # ELBv2NoScope — attribute-modify actions with unclear resource-level support
  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
    ]
    resources = ["*"]
  }

  # ObjectAccess — app.zip placeholder object (deploy.sh manages content out-of-band).
  # PutObjectTagging added 2026-09-02: the object started picking up tags_all
  # (Environment/Layer/ManagedBy/Project) and the first tag-write 403'd -- this
  # object had never been tagged before, so the gap was invisible until now.
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
    ]
    resources = ["arn:aws:s3:::${local.artifact_bucket}/app.zip"]
  }

  # LogGroupManage — logs:DescribeLogGroups already covered account-wide by
  # Foundation's policy. WAF's own log group added 2026-09-02 alongside the
  # app's -- same actions, same statement, just a second resource pair.
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:${local.log_group_name}",
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:${local.log_group_name}:*",
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:${local.waf_log_group_name}",
      "arn:aws:logs:${local.aws_region}:${local.account_id}:log-group:${local.waf_log_group_name}:*",
    ]
  }

  # PolicySelfManage — this policy's own versions + the deploy-compute-ext
  # policy + compute's app-artifact-read policy
  statement {
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
      "arn:aws:iam::${local.account_id}:policy/${local.artifact_policy}",
      "arn:aws:iam::${local.account_id}:policy/${local.deploy_policy}",
      "arn:aws:iam::${local.account_id}:policy/${local.deploy_policy_ext}",
    ]
  }

  # RoleAttach — attach/detach compute's own scoped policies (deploy-compute,
  # deploy-compute-ext, and the artifact-read policy) to their two target
  # roles (the CI deploy role and Foundation's app-role). Merged from
  # separate statements to stay under IAM's 6,144-char managed policy quota
  # — see SECURITY.md for the trade-off this accepts (any of these policies
  # can attach to either role, not strictly the original pairing).
  statement {
    effect = "Allow"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      data.aws_iam_role.deploy.arn,
      data.terraform_remote_state.foundation.outputs.app_role_arn,
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::${local.account_id}:policy/${local.deploy_policy}",
        "arn:aws:iam::${local.account_id}:policy/${local.deploy_policy_ext}",
        "arn:aws:iam::${local.account_id}:policy/${local.artifact_policy}",
      ]
    }
  }

  # TFStateObject — dev/compute/ prefix only
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/compute/*"]
  }

  # TFStateObjectDataTierRead - read-only, single-object access to the
  # data-tier state file. Needed by compute's terraform_remote_state data
  # source (reads db_secret_name / cache_secret_name from it, added
  # retroactively during the data-tier module). GetObject only, compute
  # never writes to data-tier's prefix.
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65/dev/data-tier/terraform.tfstate"]
  }

  # TFStateList
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::ce-capstone-bouncer-tfstate-f7fc4b65"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["dev/compute/*"]
    }
  }

  # RunInstances — autoscaling:CreateAutoScalingGroup internally requires
  # ec2:RunInstances to launch instances from the launch template (AWS's
  # documented requirement: docs.aws.amazon.com/AWSEC2/latest/UserGuide/
  # permissions-for-launch-templates.html). Unconditioned Resource "*",
  # matching AWS's own primary example policy for this exact scenario.
  # The ec2:LaunchTemplate / ec2:IsLaunchTemplateResource condition keys
  # were tried first (AWS's "restrict to one launch template" pattern)
  # but confirmed via repeated real 403s NOT to apply here — the Auto
  # Scaling service-authorization reference for CreateAutoScalingGroup
  # lists no launch-template condition key at all, confirming those two
  # keys only populate on a *direct* ec2:RunInstances/CreateFleet call,
  # not on the internal check CreateAutoScalingGroup performs. Eighth
  # confirmed case of this project's "looks scopeable, isn't" IAM pattern.
  statement {
    effect    = "Allow"
    actions   = ["ec2:RunInstances", "ec2:CreateTags"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_compute" {
  name        = local.deploy_policy
  description = "Scoped CI deploy-role permissions for the compute layer (terraform/environments/dev/compute)."
  policy      = data.aws_iam_policy_document.deploy_compute.json
}

resource "aws_iam_role_policy_attachment" "deploy_compute" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_compute.arn
}

# Overflow policy — S3 bucket-management, ACM, and Route53 permissions, split
# out of deploy_compute above solely to stay well clear of IAM's 6,144-char
# managed-policy size quota (adding ACM+Route53 alone left deploy_compute at
# 6,135/6,144 bytes -- technically legal but zero margin for the next
# addition). See the comment above data.aws_iam_policy_document.deploy_compute.
data "aws_iam_policy_document" "deploy_compute_ext" {

  # BucketManage — full set confirmed needed by aws_s3_bucket's own refresh:
  # every one of these corresponds to a specific sub-config the AWS provider
  # reads on every plan (versioning, encryption, PAB, lifecycle, tagging, ACL,
  # location, policy, CORS, logging, object lock, replication, request payer,
  # accelerate, website) — trimmed down once already and had to add several back.
  statement {
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:GetBucketVersioning",
      "s3:PutEncryptionConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutLifecycleConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutBucketTagging",
      "s3:GetBucketTagging",
      "s3:GetBucketLocation",
      "s3:GetBucketAcl",
      "s3:GetBucketCORS",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketWebsite",
    ]
    resources = ["arn:aws:s3:::${local.artifact_bucket}"]
  }

  # ACM — cert lifecycle for the HTTPS listener. RequestCertificate scoped
  # the same as the rest; ACM cert ARNs get a random UUID at creation
  # (unknowable in advance), so this can only scope to "any cert in this
  # account/region," not the specific certificate -- same shape as the
  # Secrets Manager name-pattern case.
  statement {
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:DeleteCertificate",
      "acm:AddTagsToCertificate",
      "acm:ListTagsForCertificate",
    ]
    resources = ["arn:aws:acm:${local.aws_region}:${local.account_id}:certificate/*"]
  }

  # Route53 — validation + alias records on the app subdomain's existing
  # hosted zone (created manually outside Terraform when the domain was
  # delegated -- see 00-shared-context.md's Domain & DNS facts). Hardcoded
  # the same way the tfstate bucket name is below, not a variable -- a
  # fixed, known-in-advance account resource. GetHostedZone added back
  # 2026-09-02: aws_route53_record's own create path looks up the zone
  # internally even with zone_id already known and no data source in play --
  # confirmed via a real 403 on aws_route53_record.app_alb_alias, not on any
  # data source. Unlike route53:ListHostedZones (account-wide, no
  # resource-level support), GetHostedZone scopes cleanly to the one zone
  # ARN, so this isn't a repeat of that case. GetChange is separate from the
  # rest because change IDs are global, not per-zone, and unknowable before
  # ChangeResourceRecordSets actually runs.
  statement {
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:GetChange",
    ]
    resources = [
      "arn:aws:route53:::hostedzone/Z09995842VAJQYF2C7UVK",
      "arn:aws:route53:::change/*",
    ]
  }

  # WAFManage — web ACL + rate-based rule create/manage/associate for the
  # /login and /buy protections. None of these wafv2 actions support
  # resource-level ARN scoping -- confirmed via AWS's own IAM service-
  # authorization reference for WAFV2 (every action below has no resource
  # type listed there, meaning IAM requires Resource "*"). Same shape as
  # ADR 0010's RunInstances precedent: unconditioned because AWS itself
  # doesn't support scoping it, not a shortcut taken here.
  statement {
    effect = "Allow"
    actions = [
      "wafv2:CreateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:GetWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:ListWebACLs",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:ListTagsForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
    ]
    resources = ["*"]
  }

  # WAFLogging — wafv2's logging-config actions have no resource type
  # listed in AWS's own IAM reference (same as WAFManage, Resource "*").
  # logs:CreateLogDelivery/DeleteLogDelivery/PutResourcePolicy/
  # DescribeResourcePolicies are the actions AWS's own WAF-to-CloudWatch
  # logging guide documents as required for the *caller* setting up
  # delivery -- AWS's log-delivery service creates the log group's resource
  # policy itself once these are granted, no manual policy JSON needed on
  # our end. logs:DescribeLogGroups already covered account-wide by
  # Foundation's policy, not repeated here.
  statement {
    effect = "Allow"
    actions = [
      "wafv2:PutLoggingConfiguration",
      "wafv2:GetLoggingConfiguration",
      "wafv2:DeleteLoggingConfiguration",
      "logs:CreateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_compute_ext" {
  name        = local.deploy_policy_ext
  description = "Scoped CI deploy-role permissions for compute's S3 bucket management, ACM certificate, Route53 records (HTTPS listener), and WAF web ACL."
  policy      = data.aws_iam_policy_document.deploy_compute_ext.json
}

resource "aws_iam_role_policy_attachment" "deploy_compute_ext" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_compute_ext.arn
}
