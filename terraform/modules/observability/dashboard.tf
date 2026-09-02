resource "aws_cloudwatch_dashboard" "app_infra" {
  dashboard_name = "${var.project}-${var.environment}-app-infra"

  dashboard_body = templatefile(
    "${path.root}/../../../../monitoring/dashboards/app-infra-dashboard.json.tpl",
    {
      region                   = var.region
      alb_arn_suffix           = coalesce(var.alb_arn_suffix, "")
      target_group_arn_suffix  = coalesce(var.target_group_arn_suffix, "")
      asg_name                 = coalesce(var.asg_name, "")
      db_instance_id           = coalesce(var.db_instance_id, "")
    }
  )
}