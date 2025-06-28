terraform {
  backend "gcs" {
    bucket = "rc11-dev" 
    prefix = "terraform/enviornment-state/dev"
  }
}