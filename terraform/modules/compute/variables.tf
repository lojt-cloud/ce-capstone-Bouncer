variable "project" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "public_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "app_security_group_id" { type = string }
variable "app_instance_profile_name" { type = string }
variable "app_role_arn" { type = string }

variable "db_secret_name" {
  description = "Secrets Manager secret name (not ARN) holding RDS credentials -- the app fetches this itself via boto3 at boot using its instance role, never a plaintext env var. From data-tier's remote state."
  type        = string
}

variable "cache_secret_name" {
  description = "Secrets Manager secret name (not ARN) holding the Redis endpoint/auth token, same pattern as db_secret_name. From data-tier's remote state."
  type        = string
}
variable "ami_id" { type = string }

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_port" {
  type    = number
  default = 8000
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "app_source_dir" {
  description = "Path to app/src, zipped and uploaded as the initial deploy artifact."
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 365
}

variable "asg_min_size" {
  type    = number
  default = 3
}

variable "asg_max_size" {
  type    = number
  default = 6
}

variable "asg_desired_capacity" {
  type    = number
  default = 3
}

variable "enable_billable_resources" {
  description = "Gates the ASG and ALB (billable EC2/ALB). Off between work sessions to control cost."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Public hostname the ALB is served under (Route53 alias + ACM cert target)."
  type        = string
  default     = "app.projectbouncer.org"
}

variable "route53_zone_id" {
  description = "Existing Route53 hosted zone ID for the app subdomain (created manually outside Terraform when the domain was delegated from Cloudflare)."
  type        = string
  default     = "Z09995842VAJQYF2C7UVK"
}