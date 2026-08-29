variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

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
variable "enable_billable_resources" {
  description = "Toggle for this layer's billable resources (NAT Gateway). Set false and re-apply to scale down between work sessions."
  type        = bool
  default     = true
}