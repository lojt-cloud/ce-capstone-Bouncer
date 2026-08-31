resource "random_id" "app_artifacts_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "app_artifacts" {
  bucket = "${var.project}-${var.environment}-app-artifacts-${random_id.app_artifacts_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "app_artifacts" {
  bucket = aws_s3_bucket.app_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_artifacts" {
  bucket = aws_s3_bucket.app_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_artifacts" {
  bucket                  = aws_s3_bucket.app_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = var.app_source_dir
  output_path = "${path.module}/.build/app.zip"
}

resource "aws_s3_object" "app_zip" {
  bucket = aws_s3_bucket.app_artifacts.id
  key    = "app.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5
}

resource "aws_s3_bucket_lifecycle_configuration" "app_artifacts" {
  bucket = aws_s3_bucket.app_artifacts.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}