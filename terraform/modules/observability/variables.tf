variable "project" {
  type = string
}
variable "environment" {
  type = string
}
variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "asg_name" {
  type    = string
  default = null
}
variable "alb_arn_suffix" {
  type    = string
  default = null
}
variable "target_group_arn_suffix" {
  type    = string
  default = null
}
variable "db_instance_id" {
  type    = string
  default = null
}
variable "cache_cluster_id" {
  type    = string
  default = null
}