variable "gcp_project_id" {
  description = "The GCP project ID where the VPC will be created."
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

variable "vpc_name" {
  description = "The name for the VPC network."
  type        = string
  default     = "app-vpc"
}

variable "gcp_region" {
  description = "The GCP region where the VPC and subnets will be created."
  type        = string
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.gcp_region))
    error_message = "The gcp_region must be a valid GCP region name (e.g., 'asia-south2')."
  }
}

variable "auto_create_subnetworks" {
  description = "When set to true, the VPC network is created in 'auto mode' and Google automatically creates one subnetwork per region. When set to false, the VPC network is created in 'custom mode' and you can define your own subnetworks."
  type        = bool
  default     = false # Best practice for production is custom mode
}

variable "routing_mode" {
  description = "The network routing mode (REGIONAL or GLOBAL). Global routing is generally recommended for GKE."
  type        = string
  default     = "GLOBAL"
  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "Routing mode must be either REGIONAL or GLOBAL."
  }
}

variable "mtu" {
  description = "The Maximum Transmission Unit (MTU) of the network in bytes. The default value is 1460. The GKE best practice is 1500 if all your VMs support it (most modern images do)."
  type        = number
  default     = 1460 # Default for broader compatibility, can be 1500 for GKE if appropriate.
}

variable "delete_default_routes_on_create" {
  description = "If set to true, default routes to the internet will be deleted. This is useful if you want to control all internet egress via a NAT gateway or other means. For this setup, we'll keep it false to allow GKE nodes to pull images, etc."
  type        = bool
  default     = false
}

// Subnetwork Configurations
variable "subnets" {
  description = "A list of subnet configurations to create within the VPC."
  type = list(object({
    name               = string
    ip_cidr_range      = string
    description        = optional(string, "Custom subnet")
    private_ip_google_access = optional(bool, true) # Recommended for GKE and other services
    purpose            = optional(string)           # e.g., PRIVATE_GKE, CLOUD_SQL
    role               = optional(string)           # e.g., ACTIVE, BACKUP (for HA VPN)
    stack_type         = optional(string, "IPV4_ONLY") # Can be IPV4_IPV6
    log_config = optional(object({
      aggregation_interval = optional(string, "INTERVAL_5_SEC")
      flow_sampling        = optional(number, 0.5)
      metadata             = optional(string, "INCLUDE_ALL_METADATA")
    }), null) # Set to null to disable flow logs by default, can be overridden
  }))
  default = []
  validation {
    condition = alltrue([
      for subnet in var.subnets : can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", subnet.name)) && length(subnet.name) <= 63
    ])
    error_message = "Subnet names must be valid RFC1035 labels (lowercase letters, numbers, hyphens, start with letter, end with letter/number, max 63 chars)."
  }
  # validation {
  #   condition = alltrue([
  #     for subnet in var.subnets : can(cidrnet(subnet.ip_cidr_range, 0)) # Basic CIDR validation
  #   ])
  #   error_message = "Each subnet ip_cidr_range must be a valid CIDR block."
  # }
}

// Firewall Rule Configurations
variable "firewall_rules" {
  description = "A list of firewall rules to create for the VPC."
  type = list(object({
    name                    = string
    description             = optional(string, "Custom firewall rule")
    direction               = optional(string, "INGRESS")
    priority                = optional(number, 1000)
    disabled                = optional(bool, false)
    source_ranges           = optional(list(string), [])
    source_tags             = optional(list(string), [])
    source_service_accounts = optional(list(string), [])
    target_tags             = optional(list(string), [])
    target_service_accounts = optional(list(string), [])
    log_config = optional(object({
      metadata = string
    }), null) # Set to null to disable logging by default

    allow = optional(list(object({
      protocol = string
      ports    = optional(list(string), [])
    })), [])

    deny = optional(list(object({
      protocol = string
      ports    = optional(list(string), [])
    })), [])
  }))
  default = []
  validation {
    condition = alltrue([
      for rule in var.firewall_rules : (length(rule.allow) > 0 || length(rule.deny) > 0)
    ])
    error_message = "Each firewall rule must have at least one 'allow' or 'deny' block."
  }
  validation {
    condition = alltrue([
      for rule in var.firewall_rules : alltrue([
        for allow_rule in rule.allow : contains(["tcp", "udp", "icmp", "esp", "ah", "sctp", "all"], lower(allow_rule.protocol))
      ]) && alltrue([
        for deny_rule in rule.deny : contains(["tcp", "udp", "icmp", "esp", "ah", "sctp", "all"], lower(deny_rule.protocol))
      ])
    ])
    error_message = "Firewall rule protocols must be one of: tcp, udp, icmp, esp, ah, sctp, or all."
  }
}

variable "secondary_ip_ranges" {
  description = "Map of secondary IP ranges for subnets, primarily for GKE Pods and Services. Keyed by subnet name."
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default = {}
  # validation {
  #   condition = alltrue([
  #     for ranges in values(var.secondary_ip_ranges) : alltrue([
  #       for range_item in ranges : can(cidrnet(range_item.ip_cidr_range, 0))
  #     ])
  #   ])
  #   error_message = "Each secondary_ip_range must be a valid CIDR block."
  # }
}

variable "enable_cloud_nat" {
  description = "If true, a Cloud NAT gateway will be created for internet access from private subnets."
  type        = bool
  default     = true # Typically needed for GKE private nodes to pull images, updates, etc.
}

variable "nat_ip_allocate_option" {
  description = "IP allocation option for Cloud NAT. Can be 'MANUAL_ONLY' or 'AUTO_ONLY'."
  type        = string
  default     = "AUTO_ONLY"
}

variable "nat_source_subnetwork_ip_ranges_to_nat" {
  description = "Specifies the options for NAT ranges. Can be 'ALL_SUBNETWORKS_ALL_IP_RANGES', 'ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES', or 'LIST_OF_SUBNETWORKS'."
  type        = string
  default     = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

variable "log_config_enable_cloud_nat" {
  description = "Enable logging for Cloud NAT."
  type        = bool
  default     = true
}

variable "log_config_filter_cloud_nat" {
  description = "Log filter for Cloud NAT. Can be 'ERRORS_ONLY', 'TRANSLATIONS_ONLY', or 'ALL'."
  type        = string
  default     = "ALL"
}

variable "tags" {
  description = "A map of tags to add to all resources created by this module."
  type        = map(string)
  default     = {}
}



variable "create_nat_gateway" {
  description = "If true, creates a Cloud Router and NAT Gateway for this VPC to allow private instances outbound internet access."
  type        = bool
  default     = false
}