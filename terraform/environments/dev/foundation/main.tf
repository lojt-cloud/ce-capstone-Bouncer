provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Layer       = "foundation"
      ManagedBy   = "terraform"
    }
  }
}

module "networking" {
  source = "../../../modules/networking"

  vpc_cidr                  = "10.0.0.0/16"
  availability_zones        = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnet_cidrs       = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs      = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  name_prefix               = "${var.project_name}-${var.environment}"
  enable_billable_resources = var.enable_billable_resources
}
module "security" {
  source = "../../../modules/security"

  vpc_id      = module.networking.vpc_id
  name_prefix = "${var.project_name}-${var.environment}"
}
data "aws_caller_identity" "current" {}

module "iam" {
  source = "../../../modules/iam"

  name_prefix      = "${var.project_name}-${var.environment}"
  project_name     = var.project_name
  account_id       = data.aws_caller_identity.current.account_id
  deploy_role_name = var.deploy_role_name
  tfstate_bucket   = var.tfstate_bucket
  aws_region       = var.aws_region
}