resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-${var.environment}-app-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.app_instance_profile_name
  }

  vpc_security_group_ids = [var.app_security_group_id]

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    aws_region       = var.aws_region
    app_bucket       = aws_s3_bucket.app_artifacts.bucket
    app_artifact_key = aws_s3_object.app_zip.key
    app_port         = var.app_port
    cw_agent_config = templatefile("${path.module}/templates/cw-agent-config.json.tpl", {
      app_log_group_name = aws_cloudwatch_log_group.app.name
    })
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-${var.environment}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}