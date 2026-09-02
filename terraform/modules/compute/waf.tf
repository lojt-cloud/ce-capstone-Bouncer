# WAF web ACL on the ALB, rate-based rules on /login and /buy. Gated by
# enable_billable_resources like the ALB/ASG -- WAF is billable ($5/mo per
# web ACL + $1/mo per rule, see COSTS.md), not a resource to leave running
# between sessions.
resource "aws_wafv2_web_acl" "app" {
  count = var.enable_billable_resources ? 1 : 0

  name        = "${var.project}-${var.environment}-app-waf"
  description = "Rate-based protection for the login and buy endpoints."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "RateLimitLogin"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_login_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/login"
            positional_constraint = "EXACTLY"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-waf-login-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitBuy"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_buy_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/buy"
            positional_constraint = "EXACTLY"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-waf-buy-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-${var.environment}-waf-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  count = var.enable_billable_resources ? 1 : 0

  resource_arn = aws_lb.app[0].arn
  web_acl_arn  = aws_wafv2_web_acl.app[0].arn
}