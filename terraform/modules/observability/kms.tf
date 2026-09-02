data "aws_caller_identity" "current" {}

resource "aws_kms_key" "sns_alerts" {
  description             = "CMK for the ${var.project}-${var.environment} observability alerts SNS topic"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountRootFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowCloudWatchAlarmsToPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "sns_alerts" {
  name          = "alias/${var.project}-${var.environment}-sns-alerts"
  target_key_id = aws_kms_key.sns_alerts.key_id
}