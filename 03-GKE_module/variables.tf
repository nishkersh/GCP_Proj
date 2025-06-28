variable "gcp_project_id" {
  description = "The GCP project ID where the GKE cluster will be created."
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
  description = "The GCP region where the GKE cluster will be created."
  type        = string
}

variable "cluster_name" {
  description = "The name for the GKE cluster."
  type        = string
  default     = "app-cluster"
}

variable "network_self_link" {
  description = "The self_link of the VPC network to deploy GKE into."
  type        = string
}

variable "subnet_self_link" {
  description = "The self_link of the subnetwork to deploy GKE into (primary range for nodes)."
  type        = string
}

variable "pods_ip_range_name" {
  description = "The name of the secondary IP range in the subnetwork used for GKE Pods."
  type        = string
}

variable "services_ip_range_name" {
  description = "The name of the secondary IP range in the subnetwork used for GKE Services."
  type        = string
}

variable "master_ipv4_cidr_block" {
  description = "The /28 CIDR block for the GKE master's internal IP range. Must be unique and not overlap with other networks. Required for private clusters."
  type        = string
  # validation {
  #   condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/28$", var.master_ipv4_cidr_block))
  #   error_message = "master_ipv4_cidr_block must be a valid /28 CIDR block (e.g., '172.16.0.0/28')."
  # }
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the GKE cluster. Use a specific version or a channel like 'stable', 'regular', 'rapid'. E.g., '1.28' or 'stable'. If null, uses the default version for the region."
  type        = string
  default     = "1.28" # Specify a recent, stable version. Check GCP for latest supported versions in the region.
}

variable "release_channel" {
  description = "The GKE release channel. Can be 'STABLE', 'REGULAR', 'RAPID', or 'UNSPECIFIED' (to use kubernetes_version directly). Using a channel is recommended for managed upgrades."
  type        = string
  default     = "STABLE" # STABLE channel is recommended for production.
  validation {
    condition     = contains(["STABLE", "REGULAR", "RAPID", "UNSPECIFIED"], upper(var.release_channel))
    error_message = "Release channel must be one of: STABLE, REGULAR, RAPID, UNSPECIFIED."
  }
}

variable "enable_private_nodes" {
  description = "If true, GKE nodes will not have public IP addresses. Recommended for security."
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "If true, the GKE master API endpoint will only be accessible from within the VPC. Requires master_authorized_networks to be configured for access (e.g., from bastion)."
  type        = bool
  default     = true
}

variable "master_authorized_networks_config" {
  description = "Configuration for master authorized networks. Allows specific CIDR blocks to access the GKE master endpoint. Required if enable_private_endpoint is true."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  default = [] # Example: [{ display_name = "bastion-access", cidr_block = "BASTION_PUBLIC_IP/32" }]
               # This needs to be populated with actual IPs that need master access.
  # validation {
  #   condition = alltrue([
  #     for config in var.master_authorized_networks_config : can(cidrnet(config.cidr_block, 0))
  #   ])
  #   error_message = "Each cidr_block in master_authorized_networks_config must be a valid CIDR."
  # }
}


variable "node_pools" {
  description = "A list of GKE node pool configurations."
  type = list(object({
    name                = string
    machine_type        = optional(string, "e2-medium")
    min_node_count      = optional(number, 1) # Per zone for regional clusters
    max_node_count      = optional(number, 3) # Per zone for regional clusters
    initial_node_count  = optional(number, 1) # Per zone for regional clusters
    disk_type           = optional(string, "pd-balanced")
    disk_size_gb        = optional(number, 50)
    image_type          = optional(string, "COS_CONTAINERD") # COS_CONTAINERD or UBUNTU_CONTAINERD
    preemptible         = optional(bool, false)
    spot                = optional(bool, false) # Spot VMs are cheaper but can be preempted. Good for dev/test or fault-tolerant workloads.
    enable_secure_boot  = optional(bool, true)
    enable_integrity_monitoring = optional(bool, true)
    oauth_scopes = optional(list(string), [ # Minimal scopes recommended for Workload Identity
      "https://www.googleapis.com/auth/devstorage.read_only", # For pulling images from GCR/Artifact Registry
      "https://www.googleapis.com/auth/logging.write",       # For Cloud Logging
      "https://www.googleapis.com/auth/monitoring",          # For Cloud Monitoring
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/trace.append"         # For Cloud Trace
    ])
    node_labels = optional(map(string), {})
    node_tags   = optional(list(string), [])
    service_account_email = optional(string, null) # If null, uses default GKE node SA. For Workload Identity, this is fine.
                                                  # If not using WI for node-level permissions, provide a custom SA.
  }))
  default = [
    {
      name = "default-pool"
    }
  ]
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for the cluster, allowing Kubernetes service accounts to impersonate Google service accounts."
  type        = bool
  default     = true # Highly recommended
}

variable "identity_namespace" {
  description = "The workload identity namespace. Usually `PROJECT_ID.svc.id.goog`."
  type        = string
  default     = "" # Will be constructed if left empty
}

variable "enable_shielded_nodes" {
  description = "Enable Shielded GKE Nodes for all node pools (Secure Boot, Integrity Monitoring, vTPM)."
  type        = bool
  default     = true
}

variable "enable_vertical_pod_autoscaling" {
  description = "Enable Vertical Pod Autoscaling (VPA) for the cluster."
  type        = bool
  default     = true
}

variable "enable_http_load_balancing" {
  description = "Enable the HTTP (L7) load balancing addon, required for GKE Ingress."
  type        = bool
  default     = true
}

variable "database_encryption_key_name" {
  description = "The KMS key name for etcd encryption at rest. If null, Google-managed encryption is used."
  type        = string
  default     = null # Example: "projects/PROJECT_ID/locations/REGION/keyRings/RING_NAME/cryptoKeys/KEY_NAME"
}

variable "maintenance_policy_recurrence" {
  description = "Maintenance window recurrence. E.g., 'FREQ=WEEKLY;BYDAY=SA' for every Saturday. If null, GKE picks one."
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SU" # Every Sunday
}

variable "maintenance_policy_start_time" {
  description = "Start time for the recurring maintenance window in RFC3339 Zulu format (e.g., '2023-01-01T02:00:00Z')."
  type        = string
  default     = "2025-07-13T02:00:00Z" # Example: Next suitable Sunday, 2 AM UTC
}

variable "maintenance_policy_end_time" {
  description = "End time for the recurring maintenance window in RFC3339 Zulu format (e.g., '2023-01-01T06:00:00Z')."
  type        = string
  default     = "2025-07-13T06:00:00Z" # Example: Next suitable Sunday, 6 AM UTC (4-hour window)
}

variable "gke_cluster_service_account_email" {
  description = "Optional. The email of a custom service account for the GKE control plane to use. If not specified, a Google-managed SA is used."
  type        = string
  default     = null
}

variable "gke_node_service_account_email" {
  description = "Optional. The email of a custom service account for GKE nodes. If not specified, the Compute Engine default SA is used. For Workload Identity, this is less critical but can be set for node-level permissions if needed."
  type        = string
  default     = null
}

variable "cluster_resource_labels" {
  description = "Labels to apply to the GKE cluster resource itself."
  type        = map(string)
  default     = {}
}

variable "remove_default_node_pool" {
  description = "Whether to remove the default node pool created by GKE. Set to true if you define all your node pools via the `node_pools` variable."
  type        = bool
  default     = true # Recommended if  manage all node pools explicitly
}

variable "default_pool_initial_node_count" {
  description = "Initial number of nodes for the default node pool. Only used if remove_default_node_pool is false."
  type        = number
  default     = 1 
}

variable "tags" {
  description = "A map of tags to add to all resources created by this module."
  type        = map(string)
  default     = {}
}

# variable "gke_enable_public_endpoint" {
#   description = "Controls if the private cluster's master also has a public endpoint. If true, master_authorized_networks can include public IPs."
#   type        = bool
#   default     = false
# }

variable "cluster_deletion_protection" {
  description = "If true, prevents the GKE cluster from being accidentally destroyed. Set to false for dev/test environments."
  type        = bool
  default     = true // A safe default for production
}