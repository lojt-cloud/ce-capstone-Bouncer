variable "vpc_id" {
  description = "VPC ID these security groups belong to"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource Name tags"
  type        = string
}

variable "app_port" {
  description = "Port the app tier listens on (Gunicorn), reachable only from the ALB"
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "Port RDS listens on. Defaults to PostgreSQL; confirm/override in the data-tier module"
  type        = number
  default     = 5432
}

variable "cache_port" {
  description = "Port ElastiCache Redis listens on"
  type        = number
  default     = 6379
}