variable "gcp_project_id" {
  description = "The GCP project ID where the Cloud SQL instance will be created."
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

variable "instance_name" {
  description = "The name of the Cloud SQL instance. This should be unique within the project."
  type        = string
  default     = "app-postgres-db"
}

variable "gcp_region" {
  description = "The GCP region where the Cloud SQL instance will be located."
  type        = string
}

variable "database_version" {
  description = "The version of PostgreSQL to use (e.g., POSTGRES_15, POSTGRES_16, POSTGRES_16 but make ssure to see the the deprecation year)."
  type        = string
  default     = "POSTGRES_15" 
}

variable "tier" {
  description = "The machine type for the Cloud SQL instance (e.g., db-f1-micro, db-g1-small, or custom like db-custom-2-4096)."
  type        = string
  default     = "db-f1-micro" # Smallest tier, suitable for dev/testing. Will be hanged at prod.
}

variable "availability_type" {
  description = "The availability type of the Cloud SQL instance. 'ZONAL' for a single zone, or 'REGIONAL' for high availability (recommended for prod)."
  type        = string
  default     = "ZONAL" # For dev. Use "REGIONAL" for production.
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "Availability type must be either ZONAL or REGIONAL."
  }
}

variable "disk_type" {
  description = "The type of storage for the Cloud SQL instance (PD_SSD or PD_HDD)."
  type        = string
  default     = "PD_SSD" # SSD is recommended for most database workloads
}

variable "disk_autoresize" {
  description = "Whether to enable automatic disk resizing."
  type        = bool
  default     = true
}

variable "disk_autoresize_limit" {
  description = "The maximum size in GB that the disk can be auto-resized to. 0 means no limit."
  type        = number
  default     = 0 # No limit by default, consider setting one for production cost control.
}

variable "disk_size" {
  description = "The initial size of the data disk in GB."
  type        = number
  default     = 20 # Minimum is 10GB for SSD.
}

variable "backup_configuration" {
  description = "Configuration for automated backups."
  type = object({
    enabled            = optional(bool, true)
    start_time         = optional(string, "03:00") # HH:MM format in UTC
    location           = optional(string, null)    # Backup location (region). If null, uses instance region.
    point_in_time_recovery_enabled = optional(bool, true) # Requires binary_log_enabled
    transaction_log_retention_days = optional(number, 7) # For PITR
  })
  default = {} # Uses the optional defaults defined above
}

variable "ip_configuration" {
  description = "IP configuration for the Cloud SQL instance."
  type = object({
    ipv4_enabled    = optional(bool, true)
    private_network_self_link = optional(string, null) # self_link of the VPC network for private IP
    ssl_mode     = optional(string, "ENCRYPTED_ONLY")
    allocated_ip_range_name = optional(string, null) # Name of the allocated IP range for private services access if needed
  })
  default = {
    ipv4_enabled    = true
    ssl_mode     = "ENCRYPTED_ONLY"
  }
}

variable "maintenance_window_day" {
  description = "The day of the week (1-7, 1=Monday) for the maintenance window."
  type        = number
  default     = 7 # Sunday
  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "The hour of the day (0-23, UTC) for the maintenance window."
  type        = number
  default     = 3 # 3 AM UTC
  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}

variable "insights_config" {
  description = "Configuration for Cloud SQL Insights."
  type = object({
    query_insights_enabled  = optional(bool, true)
    query_string_length     = optional(number, 1024)
    record_application_tags = optional(bool, false)
    record_client_address   = optional(bool, false)
  })
  default = {}
}

variable "deletion_protection" {
  description = "Whether or not the Cloud SQL instance should be protected against accidental deletion."
  type        = bool
  default     = true # Recommended for production databases
}

variable "user_name" {
  description = "The name for the default database user to be created."
  type        = string
}

variable "user_password_secret_id" {
  description = "The ID of the Google Secret Manager secret containing the password for the default database user. Format: projects/<PROJECT_ID>/secrets/<SECRET_ID>/versions/<VERSION_OR_LATEST>."
  type        = string
}

variable "databases" {
  description = "A list of database configurations to create on the instance."
  type = list(object({
    name      = string
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.UTF8")
  }))
  default = []
}

variable "instance_activation_policy" {
  description = "The activation policy for the instance. 'ALWAYS' or 'NEVER'. 'NEVER' is for read replicas not yet promoted."
  type        = string
  default     = "ALWAYS"
}

variable "tags" {
  description = "A map of tags to add to all resources created by this module."
  type        = map(string)
  default     = {}
}

variable "enable_default_user" {
  description = "Whether to create the default 'postgres' user. Set to false if you manage all users explicitly."
  type        = bool
  default     = false # We will create our own application user.
}
variable "vpc_private_services_connection" {
  description = "Dependency variable to ensure the VPC's private services connection is created first."
  type        = any
  default     = null
}