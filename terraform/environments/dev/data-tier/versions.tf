terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
  default_tags {
    tags = {
      Project     = "ce-capstone-bouncer"
      Environment = "dev"
      Layer       = "data-tier"
      ManagedBy   = "terraform"
    }
  }
}