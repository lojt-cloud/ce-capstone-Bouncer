variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per AZ"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per AZ"
  type        = list(string)
}

variable "name_prefix" {
  description = "Prefix for resource Name tags"
  type        = string
}
variable "enable_billable_resources" {
  description = "Toggle for billable resources (NAT Gateway). Set false and re-apply to scale down between work sessions."
  type        = bool
  default     = true
}
variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention for VPC flow logs"
  type        = number
  default     = 14
}