terraform {
  required_version = "= 1.17.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 8.9.0"
    }
  }
}

provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.deploy_service_account
  default_labels = {
    managed_by  = "terraform"
    environment = var.environment
  }
}