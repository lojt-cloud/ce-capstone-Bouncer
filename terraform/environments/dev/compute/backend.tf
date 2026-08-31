terraform {
  backend "s3" {
    bucket       = "ce-capstone-bouncer-tfstate-f7fc4b65"
    key          = "dev/compute/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}