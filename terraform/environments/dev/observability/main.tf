locals {
  project     = var.project_name
  environment = var.environment

  alb_arn          = data.terraform_remote_state.compute.outputs.alb_arn
  target_group_arn = data.terraform_remote_state.compute.outputs.target_group_arn

  alb_arn_suffix          = local.alb_arn != null ? split(":loadbalancer/", local.alb_arn)[1] : null
  target_group_arn_suffix = local.target_group_arn != null ? "targetgroup/${split(":targetgroup/", local.target_group_arn)[1]}" : null

  cache_replication_group_id = data.terraform_remote_state.data_tier.outputs.cache_replication_group_id
  cache_cluster_id           = local.cache_replication_group_id != null ? "${local.cache_replication_group_id}-001" : null
}

module "observability" {
  source = "../../../modules/observability"

  project     = local.project
  environment = local.environment
  region      = "eu-central-1"

  asg_name                = data.terraform_remote_state.compute.outputs.asg_name
  alb_arn_suffix          = local.alb_arn_suffix
  target_group_arn_suffix = local.target_group_arn_suffix
  db_instance_id          = data.terraform_remote_state.data_tier.outputs.db_instance_id
  cache_cluster_id        = local.cache_cluster_id
}