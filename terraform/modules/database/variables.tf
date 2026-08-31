variable "project" { type = string }
variable "environment" { type = string }

variable "private_subnet_ids" { type = list(string) }
variable "db_security_group_id" { type = string }
variable "app_role_arn" { type = string } # Foundation's shared EC2 app role -- gets a scoped secretsmanager:GetSecretValue attachment here

variable "instance_class" {
  description = "db.t4g.micro -- Graviton2, free-tier eligible alongside db.t3.micro."
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL major version only -- AWS auto-selects the latest supported minor at create time."
  type        = string
  default     = "17"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "storage_type" {
  description = "gp2, not gp3 -- AWS's Free Tier docs still name gp2 specifically for the free 20GB; gp3 free-tier eligibility isn't confirmed. Price gap at 20GB is under $2/mo either way."
  type        = string
  default     = "gp2"
}

variable "db_name" {
  type    = string
  default = "bouncer"
}

variable "master_username" {
  type    = string
  default = "bouncer_admin"
}

variable "backup_retention_days" {
  description = "Automated backup retention. 1 day -- backups configured (not skipped outright) but minimal, since this holds no real data to protect."
  type        = number
  default     = 1
}

variable "enable_billable_resources" {
  description = "Gates the RDS instance itself. Off + re-apply destroys the DB (skip_final_snapshot/no deletion_protection) -- see COSTS.md."
  type        = bool
  default     = true
}