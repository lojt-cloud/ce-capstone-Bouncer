resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-${var.environment}-observability-alerts"
  kms_master_key_id = aws_kms_key.sns_alerts.key_id
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# 1. 5xx error count -- target-level (app 500s) + ELB-level (no healthy
# target / timeout) summed. Raw count, not percentage -- this environment's
# traffic volume is low enough that percentage would be noisy (1 request =
# 100%). Eyeballed threshold, not yet live-fire verified -- see task list.
resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "${var.project}-${var.environment}-high-5xx-rate"
  alarm_description   = "Combined target + ELB 5xx responses exceeded 5 in a 5-minute window"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "e1"
    expression  = "m1 + m2"
    label       = "Total 5xx"
    return_data = true
  }
  metric_query {
    id = "m1"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = { LoadBalancer = coalesce(var.alb_arn_suffix, "") }
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    id = "m2"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = { LoadBalancer = coalesce(var.alb_arn_suffix, "") }
      period      = 300
      stat        = "Sum"
    }
  }
}

# 2. Unhealthy host count -- any unhealthy target matters on a 3-instance
# minimum ASG. 2 consecutive periods avoids alerting on a transient blip
# mid-deploy/instance-refresh.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name        = "${var.project}-${var.environment}-unhealthy-hosts"
  alarm_description = "At least 1 target group host unhealthy for 2 consecutive minutes"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    TargetGroup  = coalesce(var.target_group_arn_suffix, "")
    LoadBalancer = coalesce(var.alb_arn_suffix, "")
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# 3. RDS load (CPU) -- db.t4g.micro is burstable; sustained high CPU over
# two periods means burst credits are being spent down, not a brief spike.
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name        = "${var.project}-${var.environment}-rds-high-cpu"
  alarm_description = "RDS CPU utilization above 80% for 10 consecutive minutes"
  namespace         = "AWS/RDS"
  metric_name       = "CPUUtilization"
  dimensions = {
    DBInstanceIdentifier = coalesce(var.db_instance_id, "")
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgetsToPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
      }
    ]
  })
}
