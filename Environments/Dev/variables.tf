variable "gcp_project_id" {
  description = "The GCP project ID."
  type        = string
  default     = "it-devops-tf" # Your specified default project
}

variable "gcp_project_id_prefix" {
  description = "A short prefix derived from the project ID, used for naming resources. Max 6-10 chars, lowercase, no special symbols other than hyphen if needed at end."
  type        = string
  default     = "itd" # Example: short for it-devops-tf
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,28}[a-z0-9])?$", var.gcp_project_id_prefix)) && length(var.gcp_project_id_prefix) <= 30
    error_message = "Project ID prefix must be 1-30 chars, lowercase letters, numbers, or hyphens, starting/ending with letter/number."
  }
}

variable "environment" {
  description = "The deployment environment name."
  type        = string
  default     = "dev"
}

variable "gcp_region" {
  description = "The GCP region for all resources in this environment."
  type        = string
  default     = "asia-south2" # Your specified region
}

variable "gcp_zone_a" {
  description = "Primary GCP zone within the region (e.g., for Bastion host)."
  type        = string
  default     = "asia-south2-a" # Make sure this zone exists in your chosen region
}

// VPC Variables
variable "vpc_name" {
  description = "Name for the VPC network."
  type        = string
  default     = "app-vpc"
}

variable "vpc_subnets" {
  description = "Configuration for VPC subnets."
  type = list(object({
    name                    = string
    ip_cidr_range           = string
    description             = optional(string)
    purpose                 = optional(string) # e.g., PRIVATE_GKE
    private_ip_google_access = optional(bool, true)
    log_config_enable       = optional(bool, false) # Enable flow logs for this subnet?
  }))
  default = [
    {
      name          = "gke-subnet"
      ip_cidr_range = "10.10.0.0/20" # For GKE nodes, pods, services
      description   = "Subnet for GKE cluster resources"
      purpose       = "PRIVATE_GKE" # Important for GKE interaction with Google APIs if using private nodes
      log_config_enable = true
    },
    {
      name          = "db-subnet"
      ip_cidr_range = "10.10.16.0/24" # For Cloud SQL
      description   = "Subnet for Cloud SQL instances"
      log_config_enable = false
    },
    {
      name          = "mgmt-subnet"
      ip_cidr_range = "10.10.17.0/24" # For Bastion host, other management VMs
      description   = "Subnet for management resources like Bastion"
      log_config_enable = false
    }
  ]
}

variable "vpc_secondary_ip_ranges" {
  description = "Secondary IP ranges for subnets, primarily for GKE."
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default = {
    "gke-subnet" = [ # Must match a subnet name from vpc_subnets
      {
        range_name    = "gke-pods-range"
        ip_cidr_range = "10.20.0.0/16" # For GKE Pods
      },
      {
        range_name    = "gke-services-range"
        ip_cidr_range = "10.30.0.0/20" # For GKE Services (ClusterIPs)
      }
    ]
  }
}

variable "vpc_firewall_rules" {
  description = "Custom firewall rules for the VPC."
  type        = any # Using 'any' for brevity, structure defined in VPC module
  default     = []  # We'll define basic rules in main.tf for clarity or rely on module defaults
}

// Bastion Host Variables
variable "bastion_machine_type" {
  description = "Machine type for the Bastion host."
  type        = string
  default     = "e2-small" # Slightly larger than micro for dev if needed
}



// GKE Variables
variable "gke_cluster_name" {
  description = "Name for the GKE cluster."
  type        = string
  default     = "app-cluster"
}

variable "gke_master_ipv4_cidr_block" {
  description = "Dedicated /28 CIDR for GKE master private endpoint."
  type        = string
  default     = "172.16.0.16/28" # Ensure this doesn't overlap
}

variable "gke_master_authorized_networks" {
  description = "Networks authorized to access GKE master endpoint."
  type = list(object({
    display_name = string
    cidr_block   = string
  }))
  default = [
    # Example: Add your bastion's public IP here after it's created,
    # or your corporate VPN range.
    # {
    #   display_name = "bastion-access"
    #   cidr_block   = "YOUR_BASTION_PUBLIC_IP/32" # Placeholder
    # }
  ]
}

variable "gke_node_pools" {
  description = "Configuration for GKE node pools."
  type        = any # Using 'any' for brevity, structure defined in GKE module
  default = [
    {
      name               = "default-pool"
      machine_type       = "e2-medium"
      min_node_count     = 1
      max_node_count     = 2 # Keep dev small
      initial_node_count = 1
      disk_size_gb       = 30
      spot               = true # Use Spot VMs for dev to save cost
    }
  ]
}

// Cloud SQL (PostgreSQL) Variables
variable "db_instance_name" {
  description = "Name for the Cloud SQL PostgreSQL instance."
  type        = string
  default     = "app-pg-db"
}

variable "db_tier" {
  description = "Machine tier for the Cloud SQL instance."
  type        = string
  default     = "db-f1-micro" # Smallest for dev
}

variable "db_availability_type" {
  description = "Availability type for Cloud SQL (ZONAL or REGIONAL)."
  type        = string
  default     = "ZONAL" # Zonal for dev
}

variable "db_disk_size_gb" {
  description = "Disk size for Cloud SQL."
  type        = number
  default     = 20
}

variable "db_user_name" {
  description = "Database username for the application."
  type        = string
  default     = "app_user_dev"
}

variable "db_user_password_secret_id" {
  description = "Full ID of the Secret Manager secret for the DB user password (projects/PROJECT_ID/secrets/SECRET_NAME/versions/VERSION)."
  type        = string
  # This MUST be provided in terraform.tfvars
}

variable "db_databases" {
  description = "Databases to create in the Cloud SQL instance."
  type = list(object({
    name      = string
    charset   = optional(string)
    collation = optional(string)
  }))
  default = [
    { name = "app_db_dev" }
  ]
}

// Artifact Registry Variables
variable "ar_repository_id" {
  description = "ID for the Artifact Registry repository."
  type        = string
  default     = "app-images"
}

variable "ar_immutable_tags" {
  description = "Whether tags in Artifact Registry should be immutable."
  type        = bool
  default     = false # More convenient for dev to overwrite tags like 'latest'
}

// ALB Variables
variable "alb_load_balancer_name" {
  description = "Base name for the Application Load Balancer."
  type        = string
  default     = "app-frontend-alb"
}

variable "alb_domain_names" {
  description = "List of domain names for the ALB (e.g., ['rc11.dev.com'])."
  type        = list(string)
  default     = ["rc11.dev.com"] # My specified dev domain
}

variable "alb_backend_services_config" {
  description = "Configuration for ALB backend services. NEGs will be populated later."
  type        = any # Using 'any' for brevity, structure defined in ALB module
  default = {
    "frontend-svc" = { # Logical name for the frontend service
      port_name    = "http" # Assuming GKE service for frontend is named 'http' on port 80/8080
      protocol     = "HTTP"
      enable_cdn   = false
      health_check_config = {
        type         = "HTTP"
        request_path = "/" # Frontend should serve 200 on root path
      }
      # gke_negs will be empty initially, populated after app deployment
      gke_negs = []
    }
    # If backend API is a separate GKE service, add its config here:
    # "backend-api-svc" = {
    #   port_name = "http"
    #   protocol  = "HTTP"
    #   health_check_config = {
    #     type         = "HTTP"
    #     request_path = "/api/health" # Example health endpoint for backend
    #   }
    #   gke_negs = []
    # }
  }
}

variable "alb_url_map_default_service_backend_key" {
  description = "Key of the default backend service for the ALB URL map."
  type        = string
  default     = "frontend-svc" # Default to frontend
}

variable "alb_url_map_path_matchers" {
  description = "Path matchers for the ALB URL map."
  type        = any # Using 'any' for brevity, structure defined in ALB module
  default     = []
  # Example if backend API is separate:
  # default = [
  #   {
  #     name                = "api-routes"
  #     default_service_key = "backend-api-svc" # All traffic to this path matcher goes to api
  #     path_rules = [
  #       {
  #         paths       = ["/api", "/api/*"] # Route /api and /api/* to backend
  #         service_key = "backend-api-svc"
  #       }
  #     ]
  #   }
  #   # The default service for the URL map itself would be "frontend-svc"
  # ]
}

// General Tags
variable "common_tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default = {
    "billing-code" = "project-rc11"
    "owner"        = "devops-team"
  }
}

variable "jenkins_http_source_ranges" {
  description = "List of CIDR IP ranges which can have http access to my bastion server "
  type = list(string)
  
}

variable "jenkins_ssh_source_ranges" {
  description = "List of CIDR IP ranges which can have SSH access to my Jenkins-master server "
  type = list(string)

}

variable "bastion_ssh_source_ranges" {
  description = "List of CIDR IP ranges which can have SSH access to my bastion server "
  type = list(string)
  default = [ ]
  
}

// Zscaler integration variables

variable "zs_cc_prov_url" {
  description = "The Zscaler Cloud Connector Provisioning URL."
  type        = string
  sensitive   = true
}

variable "zpa_secret_id" {
  description = "The full resource ID of the Google Secret Manager secret containing ZPA API credentials."
  type        = string
}

variable "ssh_public_key" {
  description = "The public SSH key content for the Hub bastion host."
  type        = string
  sensitive   = true
}