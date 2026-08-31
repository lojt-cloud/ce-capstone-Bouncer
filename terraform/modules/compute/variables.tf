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

variable "ami_id" { type = string }

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_port" {
  type    = number
  default = 8000
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
  description = "Gates the ASG (billable EC2). Off between work sessions to control cost."
  type        = bool
  default     = true
}