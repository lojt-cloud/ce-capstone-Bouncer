variable "drift_alert_email" {
  description = "Email address to receive nightly Terraform drift-detection alerts"
  type        = string
  default     = "lojtiboy@gmail.com"
}

resource "aws_sns_topic" "drift_alerts" {
  name              = "${var.project_name}-${var.environment}-drift-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "drift_alerts_email" {
  topic_arn = aws_sns_topic.drift_alerts.arn
  protocol  = "email"
  endpoint  = var.drift_alert_email
}

data "aws_iam_role" "deploy" {
  name = "ce-capstone-bouncer-deploy"
}

data "aws_iam_policy_document" "deploy_foundation_sns" {
  # Topic-level actions
  statement {
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
    resources = [aws_sns_topic.drift_alerts.arn]
  }

  # Subscription-level actions (subscription ARN = topic ARN + :subscription-id)
  statement {
    effect = "Allow"
    actions = [
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:SetSubscriptionAttributes",
    ]
    resources = ["${aws_sns_topic.drift_alerts.arn}:*"]
  }
}

resource "aws_iam_policy" "deploy_foundation_sns" {
  name        = "${var.project_name}-${var.environment}-deploy-foundation-sns"
  description = "Allows the CI deploy role to publish nightly drift-detection alerts to SNS."
  policy      = data.aws_iam_policy_document.deploy_foundation_sns.json
}

resource "aws_iam_role_policy_attachment" "deploy_foundation_sns" {
  role       = data.aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy_foundation_sns.arn
}

output "drift_alerts_topic_arn" {
  description = "SNS topic ARN for nightly drift-detection alerts"
  value       = aws_sns_topic.drift_alerts.arn
}
