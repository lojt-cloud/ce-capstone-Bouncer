data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "ce-capstone-bouncer-tfstate-f7fc4b65"
    key    = "dev/foundation/terraform.tfstate"
    region = "eu-central-1"
  }
}

data "terraform_remote_state" "data_tier" {
  backend = "s3"
  config = {
    bucket = "ce-capstone-bouncer-tfstate-f7fc4b65"
    key    = "dev/data-tier/terraform.tfstate"
    region = "eu-central-1"
  }
}