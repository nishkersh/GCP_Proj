# /zscaler_spoke_connectors/variables.tf

# ------------------------------------------------------------------------------
# GCP Project and Region Configuration
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where the App Connectors will be deployed."
  type        = string
}

variable "region" {
  description = "The GCP region for the App Connector resources."
  type        = string
}

variable "zones" {
  description = "A list of GCP zones within the specified region to deploy App Connector VMs for High Availability. e.g., [\"us-central1-a\", \"us-central1-b\"]"
  type        = list(string)
  validation {
    condition     = length(var.zones) > 0
    error_message = "At least one zone must be provided for deployment."
  }
}

# ------------------------------------------------------------------------------
# Spoke VPC and Subnet Configuration (Brownfield)
# ------------------------------------------------------------------------------

variable "spoke_vpc_name" {
  description = "The name of the existing Spoke VPC where the App Connectors will be deployed."
  type        = string
}

variable "ac_subnet_name" {
  description = "The name of the new subnet to be created within the Spoke VPC for the App Connectors."
  type        = string
}

variable "ac_subnet_cidr" {
  description = "The IPv4 CIDR range for the new App Connector subnet."
  type        = string
}

# ------------------------------------------------------------------------------
# Zscaler App Connector Configuration
# ------------------------------------------------------------------------------

variable "ac_instance_type" {
  description = "The machine type for the App Connector VMs."
  type        = string
  default     = "n2-standard-4"
}

variable "ac_count_per_zone" {
  description = "The number of App Connector VMs to deploy in each specified availability zone."
  type        = number
  default     = 1 # For a total of 2 VMs in a 2-zone deployment
}

# ------------------------------------------------------------------------------
# ZPA Provider and Secret Configuration
# ------------------------------------------------------------------------------

variable "zpa_secret_id" {
  description = "The ID of the secret in Google Secret Manager containing ZPA credentials. e.g., projects/PROJECT_ID/secrets/SECRET_NAME."
  type        = string
}

# ------------------------------------------------------------------------------
# Naming and Tagging
# ------------------------------------------------------------------------------

variable "name_prefix" {
  description = "A short prefix (e.g., 'zs-spoke') to be used for naming all resources."
  type        = string
}