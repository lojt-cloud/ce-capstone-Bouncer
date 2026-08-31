variable "project" { type = string }
variable "environment" { type = string }

variable "private_subnet_ids" { type = list(string) }
variable "cache_security_group_id" { type = string }
variable "app_role_arn" { type = string }

variable "node_type" {
  description = "cache.t4g.micro -- Graviton2, same family choice as RDS."
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine_version" {
  description = "Redis OSS 7.1 -- latest ElastiCache-supported Redis OSS version as of writing."
  type        = string
  default     = "7.1"
}

variable "enable_billable_resources" {
  description = "Gates the replication group itself. Off + re-apply destroys it -- fine here, this holds only ephemeral lockout counters and session tokens, no data of record."
  type        = bool
  default     = true
}