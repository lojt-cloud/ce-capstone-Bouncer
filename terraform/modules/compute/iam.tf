locals {
  app_role_name = element(split("/", var.app_role_arn), length(split("/", var.app_role_arn)) - 1)
}

data "aws_iam_policy_document" "app_artifact_read" {
  statement {
    sid       = "ReadAppArtifact"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app_artifacts.arn}/*"]
  }
}

resource "aws_iam_policy" "app_artifact_read" {
  name   = "${var.project}-${var.environment}-compute-app-artifact-read"
  policy = data.aws_iam_policy_document.app_artifact_read.json
}

resource "aws_iam_role_policy_attachment" "app_artifact_read" {
  role       = local.app_role_name
  policy_arn = aws_iam_policy.app_artifact_read.arn
}