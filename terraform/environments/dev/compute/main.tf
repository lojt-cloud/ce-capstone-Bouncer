locals {
  project     = "ce-capstone-bouncer"
  environment = "dev"
  aws_region  = "eu-central-1"
}

module "compute" {
  source = "../../../modules/compute"

  project         = local.project
  environment     = local.environment
  aws_region      = local.aws_region
  domain_name     = "app.projectbouncer.org"
  route53_zone_id = "Z09995842VAJQYF2C7UVK"

  vpc_id                    = data.terraform_remote_state.foundation.outputs.vpc_id
  private_subnet_ids        = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  public_subnet_ids         = data.terraform_remote_state.foundation.outputs.public_subnet_ids
  alb_security_group_id     = data.terraform_remote_state.foundation.outputs.alb_security_group_id
  app_security_group_id     = data.terraform_remote_state.foundation.outputs.app_security_group_id
  app_instance_profile_name = data.terraform_remote_state.foundation.outputs.app_instance_profile_name
  app_role_arn              = data.terraform_remote_state.foundation.outputs.app_role_arn

  db_secret_name    = data.terraform_remote_state.data_tier.outputs.db_secret_name
  cache_secret_name = data.terraform_remote_state.data_tier.outputs.cache_secret_name

  ami_id            = var.ami_id
  instance_type     = var.instance_type
  app_port          = var.app_port
  health_check_path = var.health_check_path
  app_source_dir    = "${path.module}/../../../../app/src"

  asg_min_size              = var.asg_min_size
  asg_max_size              = var.asg_max_size
  asg_desired_capacity      = var.asg_desired_capacity
  enable_billable_resources = var.enable_billable_resources
}