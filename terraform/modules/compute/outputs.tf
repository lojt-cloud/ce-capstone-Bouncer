output "launch_template_id" {
  value = aws_launch_template.app.id
}

output "app_log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}

output "app_artifact_bucket_name" {
  value = aws_s3_bucket.app_artifacts.bucket
}

output "asg_name" {
  value = try(aws_autoscaling_group.app[0].name, null)
}

output "asg_arn" {
  value = try(aws_autoscaling_group.app[0].arn, null)
}