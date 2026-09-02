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
