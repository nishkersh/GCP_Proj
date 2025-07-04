# /zscaler_spoke_connectors/versions.tf

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.35.0"
    }
    zpa = {
      source  = "zscaler/zpa"
      # Pin to a specific version for production stability
      version = "~> 3.33.0"
    }
  }
}