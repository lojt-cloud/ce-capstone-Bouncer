variable "name_prefix" {
  description = "Prefix for resource names/tags"
  type        = string
}

variable "project_name" {
  description = "Project name, used to scope IAM resource ARNs"
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to build IAM ARNs"
  type        = string
}

variable "deploy_role_name" {
  description = "Name of the existing GitHub Actions OIDC deploy role"
  type        = string
}

variable "tfstate_bucket" {
  description = "Name of the Terraform remote state S3 bucket"
  type        = string
}