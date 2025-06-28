variable "gcp_project_id" {
  description = "The GCP project ID where the bastion host will be created."
  type        = string
}

variable "gcp_project_id_prefix" {
  description = "A prefix, often derived from the project ID, for naming resources."
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., 'dev', 'prod'). Used for naming resources."
  type        = string
}

variable "gcp_region" {
  description = "The GCP region where the bastion host will be created."
  type        = string
}

variable "zone" {
  description = "The GCP zone where the bastion host will be created (e.g., 'asia-south2-a')."
  type        = string
}

variable "instance_name" {
  description = "The name for the bastion host VM instance."
  type        = string
  default     = "bastion-host"
}

variable "machine_type" {
  description = "The machine type for the bastion host."
  type        = string
  default     = "e2-micro" # Cost-effective for a bastion
}

variable "boot_disk_image" {
  description = "The boot disk image for the bastion host. E.g., 'debian-cloud/debian-11' or 'cos-cloud/cos-stable'."
  type        = string
  default     = "debian-cloud/debian-11" # Debian is a common choice
}

variable "boot_disk_type" {
  description = "The type of boot disk (e.g., pd-standard, pd-balanced, pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "boot_disk_size_gb" {
  description = "The size of the boot disk in GB."
  type        = number
  default     = 20
}

variable "network_name" {
  description = "The name of the VPC network to attach the bastion host to."
  type        = string
}

variable "subnet_name" {
  description = "The name of the subnetwork to attach the bastion host to."
  type        = string
}

variable "network_tags" {
  description = "A list of network tags to apply to the bastion host instance. Used for firewall rules."
  type        = list(string)
  default     = ["bastion"]
}

variable "ssh_source_ranges" {
  description = "List of CIDR IP ranges which can have SSH access to my bastion server "
  type = list(string)
  default = [ ]
  
}

variable "create_external_ip" {
  description = "Whether to create an external IP for the bastion host. Required for direct SSH access from the internet."
  type        = bool
  default     = true
}

variable "service_account_email" {
  description = "The email of the service account to attach to the bastion host. If null, the default Compute Engine service account is used. It's recommended to use a dedicated service account with minimal privileges."
  type        = string
  default     = null
}

variable "service_account_scopes" {
  description = "List of OAuth scopes to assign to the service account. Relevant if service_account_email is provided."
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud-platform" # Broad scope
  ]
}

variable "enable_os_login" {
  description = "Whether to enable OS Login for the instance. OS Login manages SSH access using IAM permissions."
  type        = bool
  default     = true # Recommended for better IAM-based SSH management
}

variable "startup_script" {
  description = "A startup script to run when the instance is created."
  type        = string
  default     = null # Example: "#!/bin/bash\napt-get update\napt-get install -y tcpdump dnsutils"
}

variable "shielded_instance_config" {
  description = "Shielded VM configuration. Helps protect against rootkits and bootkits."
  type = object({
    enable_secure_boot          = optional(bool, true)
    enable_vtpm                 = optional(bool, true)
    enable_integrity_monitoring = optional(bool, true)
  })
  default = {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

variable "deletion_protection" {
  description = "Whether or not the bastion instance should be protected against accidental deletion."
  type        = bool
  default     = false # Set to true for production bastions 
}

variable "tags" {
  description = "A map of tags to add to all resources created by this module."
  type        = map(string)
  default     = {}
}

variable "create_static_ip" {
  description = "If true, a static external IP address will be created and assigned to the bastion. Required for GKE private endpoints."
  type        = bool
  default     = false
}