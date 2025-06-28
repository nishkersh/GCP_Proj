variable "gcp_project_id" {
  description = "The GCP project ID where the Artifact Registry repository will be created."
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
  description = "The GCP region where the Artifact Registry repository will be located. This should ideally be the same region as your GKE cluster to minimize latency and cost for image pulls."
  type        = string
}

variable "repository_id" {
  description = "The user-defined ID for the Artifact Registry repository. This will be part of the image path."
  type        = string
  default     = "app-images" # e.g., my-app-name-images
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.repository_id))
    error_message = "Repository ID must start with a letter, contain only lowercase letters, numbers, and hyphens, end with a letter or number, and be 2-63 characters long."
  }
}

variable "repository_description" {
  description = "A human-readable description for the Artifact Registry repository."
  type        = string
  default     = "Docker repository for application container images"
}

variable "repository_format" {
  description = "The format of the repository. For container images, this is 'DOCKER'."
  type        = string
  default     = "DOCKER"
  validation {
    condition     = var.repository_format == "DOCKER" # This module is specifically for Docker for now
    error_message = "Repository format must be DOCKER for this module."
  }
}

variable "kms_key_name" {
  description = "The KMS key name to be used for encrypting artifacts in the repository. If null, Google-managed encryption is used."
  type        = string
  default     = null # Example: "projects/PROJECT_ID/locations/REGION/keyRings/RING_NAME/cryptoKeys/KEY_NAME"
}

variable "immutable_tags" {
  description = "If true, image tags will be immutable in this repository. Once an image is tagged, the tag cannot be overwritten. Recommended for production to ensure tag stability."
  type        = bool
  default     = true # For production, true is generally better. For dev, false might be more convenient.
}

variable "tags" {
  description = "A map of tags to add to the repository resource."
  type        = map(string)
  default     = {}
}

variable "cleanup_policies" {
  description = "Defines cleanup policies for the repository. Map of policy IDs to policy objects."
  type = map(object({
    action      = optional(string, "DELETE") # Or "KEEP"
    condition   = optional(object({
      tag_state         = optional(string, "ANY") # "TAGGED", "UNTAGGED", "ANY"
      tag_prefixes      = optional(list(string), [])
      version_name_prefixes = optional(list(string), [])
      older_than        = optional(string, null) # e.g., "2592000s" (30 days)
      newer_than        = optional(string, null) # e.g., "604800s" (7 days)
    }), null)
    most_recent_versions = optional(object({
      keep_count        = optional(number, null) # Number of versions to keep
      package_name_prefixes = optional(list(string), [])
    }), null)
  }))
  default = {}
  # Example:
  # default = {
  #   "delete-untagged-after-30-days" = {
  #     action = "DELETE"
  #     condition = {
  #       tag_state  = "UNTAGGED"
  #       older_than = "2592000s" # 30 days
  #     }
  #   },
  #   "keep-10-prod-tags" = {
  #     action = "KEEP" # This is an exception to other DELETE rules
  #     most_recent_versions = {
  #       keep_count = 10
  #       package_name_prefixes = ["frontend-app", "backend-app"] # Assuming images are named like this
  #     }
  #     condition = {
  #       tag_prefixes = ["prod-"] # Keep if tag starts with prod-
  #       tag_state    = "TAGGED"
  #     }
  #   }
  # }
}