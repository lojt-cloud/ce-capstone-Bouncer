variable "ami_id" {
  description = "Pinned AL2023 AMI ID for eu-central-1, looked up once via SSM — never a live data source."
  type        = string
  default     = "ami-02d33cbf17ed94bf3"
}

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
  type    = bool
  default = true
}