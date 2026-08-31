locals {
  app_role_name = element(split("/", var.app_role_arn), length(split("/", var.app_role_arn)) - 1)
}

data "aws_iam_policy_document" "cache_secret_read" {
  statement {
    sid       = "ReadCacheSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.cache.arn]
  }
}

resource "aws_iam_policy" "cache_secret_read" {
  name   = "${var.project}-${var.environment}-cache-secret-read"
  policy = data.aws_iam_policy_document.cache_secret_read.json
}

resource "aws_iam_role_policy_attachment" "cache_secret_read" {
  role       = local.app_role_name
  policy_arn = aws_iam_policy.cache_secret_read.arn
}