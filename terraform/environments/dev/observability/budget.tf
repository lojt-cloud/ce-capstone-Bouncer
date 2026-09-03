# Cost guardrail scoped to this project via the Project tag. Threshold set
# from COSTS.md's confirmed steady-state monthly projection ($130.86/mo,
# eu-central-1, everything running continuously) with headroom -- not the
# earlier unverified "~EUR80-90" figure. See the Budget guardrail note in
# 00-shared-context.md for the full decision history.
#
# Reuses the existing observability-alerts SNS topic (same channel the
# CloudWatch alarms already publish to, with a confirmed working email
# subscription) rather than standing up a second one.

resource "aws_budgets_budget" "project" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = var.budget_monthly_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project_name)]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 50
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [module.observability.alerts_topic_arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [module.observability.alerts_topic_arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [module.observability.alerts_topic_arn]
  }
}
