module "networking" {
  source = "../../../modules/networking"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  name_prefix          = "${var.project_name}-${var.environment}"
}