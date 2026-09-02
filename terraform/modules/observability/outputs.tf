output "dashboard_name" {
  value = aws_cloudwatch_dashboard.app_infra.dashboard_name
}
output "dashboard_arn" {
  value = aws_cloudwatch_dashboard.app_infra.dashboard_arn
}
output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}