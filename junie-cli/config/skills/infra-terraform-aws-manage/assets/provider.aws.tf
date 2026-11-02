terraform {
  required_version = "= 1.17.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.70.0"
    }
  }
}

provider "aws" {
  region = var.region
  assume_role {
    role_arn     = var.deploy_role_arn
    session_name = "terraform"
  }
}