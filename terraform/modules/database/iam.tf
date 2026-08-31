locals {
  app_role_name = element(split("/", var.app_role_arn), length(split("/", var.app_role_arn)) - 1)
}

data "aws_iam_policy_document" "db_secret_read" {
  statement {
    sid       = "ReadDbSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "db_secret_read" {
  name   = "${var.project}-${var.environment}-database-secret-read"
  policy = data.aws_iam_policy_document.db_secret_read.json
}

resource "aws_iam_role_policy_attachment" "db_secret_read" {
  role       = local.app_role_name
  policy_arn = aws_iam_policy.db_secret_read.arn
}