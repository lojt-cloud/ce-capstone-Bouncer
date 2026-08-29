output "app_role_arn" {
  value = aws_iam_role.app.arn
}

output "app_role_name" {
  value = aws_iam_role.app.name
}

output "app_instance_profile_arn" {
  value = aws_iam_instance_profile.app.arn
}

output "app_instance_profile_name" {
  value = aws_iam_instance_profile.app.name
}