# WAF web ACL on the ALB: a Log4j/JNDI-lookup managed rule (CVE-2021-44228,
# checkov CKV_AWS_192) plus rate-based rules on /login and /buy, with
# logging to CloudWatch (checkov CKV2_AWS_31). Gated by
# enable_billable_resources like the ALB/ASG -- WAF is billable ($5/mo per
# web ACL + $1/mo per rule/managed-rule-group, see COSTS.md), not a
# resource to leave running between sessions.

resource "aws_cloudwatch_log_group" "waf" {
  count = var.enable_billable_resources ? 1 : 0

  # Name MUST start with "aws-waf-logs-" -- AWS WAF's own hard requirement
  # for a CloudWatch Logs destination, not a naming preference.
  name              = "aws-waf-logs-${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days
}

resource "aws_wafv2_web_acl" "app" {
  count = var.enable_billable_resources ? 1 : 0

  name        = "${var.project}-${var.environment}-app-waf"
  description = "Log4j protection and rate-based rules for the login and buy endpoints."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # AWSManagedRulesKnownBadInputsRuleSet includes the Log4JRCE rule, which
  # blocks JNDI-lookup payloads (CVE-2021-44228 / Log4Shell). override_action
  # "none" means: respect the rule group's own per-rule actions (Log4JRCE
  # blocks by default) rather than only counting matches.
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-${var.environment}-waf-known-bad-inputs"
      sampled_requests_enabled   = true
    }
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

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  count = var.enable_billable_resources ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.app[0].arn
  log_destination_configs = [aws_cloudwatch_log_group.waf[0].arn]

  # Session cookie and any Authorization header are never written to logs,
  # even though the app doesn't log request bodies either way -- belt and
  # suspenders on top of the app's own logging.
  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }
}