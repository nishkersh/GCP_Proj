variable "gcp_project_id" {
  description = "The GCP project ID where the ALB resources will be created."
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

variable "load_balancer_name" {
  description = "The base name for the Application Load Balancer resources."
  type        = string
  default     = "app-ext-alb"
}

variable "domain_names" {
  description = "A list of domain names for which Google-managed SSL certificates will be provisioned and associated with the load balancer (e.g., ['rc11.dev.com']). The first domain in the list will be considered the primary for naming."
  type        = list(string)
  validation {
    condition     = length(var.domain_names) > 0
    error_message = "At least one domain name must be provided."
  }
}

variable "enable_http_to_https_redirect" {
  description = "If true, an additional forwarding rule and URL map will be created to redirect HTTP traffic to HTTPS."
  type        = bool
  default     = true
}

variable "ip_address_name" {
  description = "Optional: The name of a pre-existing global static IP address to use for the load balancer. If null, an ephemeral IP will be used initially, which can be promoted to static or a new static IP will be created by this module."
  type        = string
  default     = null # If null, module creates a new static IP.
}

variable "create_static_ip" {
  description = "If true, and ip_address_name is null, a new global static IP address will be created for the load balancer. Recommended for production."
  type        = bool
  default     = true
}

variable "backend_services_config" {
  description = "Configuration for backend services. Each key is a logical name for the backend service (e.g., 'frontend-svc'), and the value is its configuration."
  type = map(object({
    description                     = optional(string, "Application backend service")
    port_name                       = optional(string, "http") # Named port on the NEGs/backends
    protocol                        = optional(string, "HTTP") # Or HTTPS, HTTP2. For GKE NEGs, this is usually HTTP as SSL is terminated at ALB.
    timeout_sec                     = optional(number, 30)
    connection_draining_timeout_sec = optional(number, 300)
    enable_cdn                      = optional(bool, false)
    cdn_policy = optional(object({
      cache_mode                   = optional(string, "CACHE_ALL_STATIC") # Or USE_ORIGIN_HEADERS, FORCE_CACHE_ALL
      default_ttl                  = optional(number, 3600)              # In seconds
      client_ttl                   = optional(number, null)
      max_ttl                      = optional(number, null)
      negative_caching             = optional(bool, false)
      negative_caching_policy      = optional(map(number), null) # e.g., {"404": 300, "502": 60}
      serve_while_stale            = optional(number, null)      # In seconds
      signed_url_cache_max_age_sec = optional(number, null)
    }), null)
    health_check_config = object({
      type                = optional(string, "HTTP") # Or HTTPS, HTTP2, TCP, SSL
      request_path        = optional(string, "/")
      port                = optional(number, null) # If null, uses backend service port_name or default for protocol
      check_interval_sec  = optional(number, 15)
      timeout_sec         = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    })
    iap_config = optional(object({ # Identity-Aware Proxy configuration
      enabled               = bool
      oauth2_client_id      = string # Secret ID for IAP OAuth2 client ID
      oauth2_client_secret  = string # Secret ID for IAP OAuth2 client secret
    }), null)
    log_config_enable   = optional(bool, true)
    log_config_sample_rate = optional(number, 1.0) # 1.0 means log all requests

    # Backends (NEGs) will be added to these backend services.
    # This variable defines the backend services; NEGs are attached in a separate step/variable.
    gke_negs = optional(list(object({ # List of GKE NEGs to attach to this backend service
      name = string # Name of the NEG (output from GKE service deployment)
      zone = string # Zone of the NEG (for zonal NEGs) - can be null for regional NEGs if supported by provider version
      # region = string # Region of the NEG (for regional NEGs) - use if NEGs are regional
    })), [])
  }))
  default = {}
}

variable "url_map_default_service_backend_key" {
  description = "The key (from backend_services_config map) of the backend service to use as the default for the URL map."
  type        = string
  default     = null # Must be set if backend_services_config is not empty
}

variable "url_map_path_matchers" {
  description = "Configuration for URL map path matchers. Allows routing based on host and path."
  type = list(object({
    name                = string # Name for this path matcher
    default_service_key = string # Key of the backend service from backend_services_config
    description         = optional(string, "Path matcher rules")
    path_rules = list(object({
      paths               = list(string) # e.g., ["/api/*", "/api/v2/*"]
      service_key         = string       # Key of the backend service from backend_services_config
      # route_action      = optional(...) # For redirects, rewrites etc.
      # url_redirect      = optional(...)
    }))
    # header_action     = optional(...)
    # host_rules can also be added here if complex host-based routing is needed beyond the primary domain.
  }))
  default = []
  # Example:
  # default = [
  #   {
  #     name                = "api-matcher"
  #     default_service_key = "backend-api-svc" # Assuming a backend_services_config key "backend-api-svc"
  #     path_rules = [
  #       {
  #         paths       = ["/api/*"]
  #         service_key = "backend-api-svc"
  #       },
  #       {
  #         paths       = ["/static/*"]
  #         service_key = "static-content-svc" # Another backend service for static assets
  #       }
  #     ]
  #   }
  # ]
}

variable "security_policy_name" {
  description = "Optional: The name of a Google Cloud Armor security policy to attach to backend services. If null, no policy is attached."
  type        = string
  default     = null # Example: "projects/PROJECT_ID/global/securityPolicies/POLICY_NAME" or just "POLICY_NAME" if in same project
}

variable "tags" {
  description = "A map of tags to add to resources created by this module."
  type        = map(string)
  default     = {}
}