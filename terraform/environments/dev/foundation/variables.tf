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
variable "deploy_role_name" {
  description = "Name of the existing GitHub Actions OIDC deploy role"
  type        = string
  default     = "ce-capstone-bouncer-deploy"
}

variable "tfstate_bucket" {
  description = "Name of the Terraform remote state S3 bucket"
  type        = string
  default     = "ce-capstone-bouncer-tfstate-f7fc4b65"
}

variable "owner" {
  description = "Tag identifying who owns/maintains this project"
  type        = string
  default     = "lojt-cloud"
}
