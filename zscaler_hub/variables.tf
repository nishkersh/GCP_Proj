# ------------------------------------------------------------------------------
# GCP Project and Region Configuration
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where the Hub VPC and resources will be deployed."
  type        = string
}

variable "region" {
  description = "The GCP region for all resources in the Hub."
  type        = string
}

variable "zones" {
  description = "A list of GCP zones within the specified region to deploy Cloud Connector VMs for High Availability. e.g., [\"us-central1-a\", \"us-central1-b\"]"
  type        = list(string)
  validation {
    condition     = length(var.zones) > 0
    error_message = "At least one zone must be provided for deployment."
  }
}

# ------------------------------------------------------------------------------
# Hub VPC and Subnet Configuration
# ------------------------------------------------------------------------------

variable "hub_vpc_name" {
  description = "The name for the new Hub VPC."
  type        = string
}

variable "cc_subnet_cidr" {
  description = "The IPv4 CIDR range for the Cloud Connector subnet."
  type        = string
}

variable "mgmt_subnet_cidr" {
  description = "The IPv4 CIDR range for the management subnet (for the bastion host)."
  type        = string
}

# ------------------------------------------------------------------------------
# Zscaler Cloud Connector Configuration
# ------------------------------------------------------------------------------

variable "cc_vm_prov_url" {
  description = "The Zscaler Cloud Connector Provisioning URL obtained from the ZIA Portal."
  type        = string
  sensitive   = true
}

variable "cc_instance_type" {
  description = "The machine type for the Cloud Connector VMs."
  type        = string
  default     = "n2-standard-2"
}

variable "cc_count_per_zone" {
  description = "The number of Cloud Connector VMs to deploy in each specified availability zone."
  type        = number
  default     = 1 # For a total of 2 VMs in a 2-zone deployment
}

# ------------------------------------------------------------------------------
# Bastion Host Configuration
# ------------------------------------------------------------------------------

variable "bastion_machine_type" {
  description = "The machine type for the Hub's bastion host."
  type        = string
  default     = "e2-small"
}

variable "bastion_ssh_public_key" {
  description = "The public SSH key content to be placed on the bastion host for administrative access."
  type        = string
  sensitive   = true
}

# ------------------------------------------------------------------------------
# Naming and Tagging
# ------------------------------------------------------------------------------

variable "name_prefix" {
  description = "A short prefix (e.g., 'zs-hub') to be used for naming all resources."
  type        = string
}