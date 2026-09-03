variable "project_name" {
  description = "Project name, used in tags and resource naming"
  type        = string
  default     = "ce-capstone-bouncer"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Tag identifying who owns/maintains this project"
  type        = string
  default     = "lojt-cloud"
}

variable "budget_monthly_limit_usd" {
  description = "Monthly cost guardrail threshold in USD, sized against COSTS.md's confirmed steady-state monthly projection with headroom"
  type        = string
  default     = "150"
}
