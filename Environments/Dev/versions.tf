terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.35.0" 
    }

    helm = {
      source = "hashicorp/helm"
      version = "3.0.2"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.37.1"
    }
  }
}