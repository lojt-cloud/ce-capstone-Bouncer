locals {
  project     = "ce-capstone-bouncer"
  environment = "dev"
}

module "database" {
  source = "../../../modules/database"

  project     = local.project
  environment = local.environment

  private_subnet_ids   = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  db_security_group_id = data.terraform_remote_state.foundation.outputs.db_security_group_id
  app_role_arn         = data.terraform_remote_state.foundation.outputs.app_role_arn

  instance_class    = var.db_instance_class
  engine_version    = var.db_engine_version
  allocated_storage = var.db_allocated_storage
  db_name           = var.db_name
  master_username   = var.db_master_username

  enable_billable_resources = var.enable_billable_resources
}

module "cache" {
  source = "../../../modules/cache"

  project     = local.project
  environment = local.environment

  private_subnet_ids      = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  cache_security_group_id = data.terraform_remote_state.foundation.outputs.cache_security_group_id
  app_role_arn            = data.terraform_remote_state.foundation.outputs.app_role_arn

  node_type      = var.cache_node_type
  engine_version = var.cache_engine_version

  enable_billable_resources = var.enable_billable_resources
}