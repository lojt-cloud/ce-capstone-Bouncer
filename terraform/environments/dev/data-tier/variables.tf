variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_engine_version" {
  type    = string
  default = "17"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "bouncer"
}

variable "db_master_username" {
  type    = string
  default = "bouncer_admin"
}

variable "enable_billable_resources" {
  description = "Gates RDS (and, once added, ElastiCache). Off + re-apply between work sessions -- destroys DB/cache content, see COSTS.md."
  type        = bool
  default     = true
}

variable "cache_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "cache_engine_version" {
  type    = string
  default = "7.1"
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

variable "owner" {
  description = "Tag identifying who owns/maintains this project"
  type        = string
  default     = "lojt-cloud"
}
