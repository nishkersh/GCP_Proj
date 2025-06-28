locals {
  module_tags = merge(var.tags, {
    terraform_module = "artifact-registry"
    environment      = var.environment
  })
  # The full repository name used for pulling/pushing images will be:
  # ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${var.repository_id}
}

resource "google_artifact_registry_repository" "default" {
  project      = var.gcp_project_id
  location     = var.gcp_region
  repository_id = var.repository_id
  description  = var.repository_description
  format       = upper(var.repository_format) # Ensure format is uppercase as expected by API
  kms_key_name = var.kms_key_name
  labels       = local.module_tags

  dynamic "docker_config" {
    # This block is only applicable if format is DOCKER.
    # Since we validate format to be DOCKER, this will always be created.
    for_each = upper(var.repository_format) == "DOCKER" ? [1] : []
    content {
      immutable_tags = var.immutable_tags
    }
  }

  dynamic "cleanup_policies" {
    for_each = var.cleanup_policies
    content {
      id     = cleanup_policies.key
      action = upper(lookup(cleanup_policies.value, "action", "DELETE"))

      dynamic "condition" {
        for_each = lookup(cleanup_policies.value, "condition", null) != null ? [cleanup_policies.value.condition] : []
        content {
          tag_state             = upper(lookup(condition.value, "tag_state", "ANY"))
          tag_prefixes          = lookup(condition.value, "tag_prefixes", [])
          version_name_prefixes = lookup(condition.value, "version_name_prefixes", [])
          older_than            = lookup(condition.value, "older_than", null)
          newer_than            = lookup(condition.value, "newer_than", null)
        }
      }

      dynamic "most_recent_versions" {
        for_each = lookup(cleanup_policies.value, "most_recent_versions", null) != null ? [cleanup_policies.value.most_recent_versions] : []
        content {
          keep_count            = lookup(most_recent_versions.value, "keep_count", null)
          package_name_prefixes = lookup(most_recent_versions.value, "package_name_prefixes", [])
        }
      }
    }
  }

  # Cleanup policy purge is a newer feature, ensure provider version supports it if used.
  # cleanup_policy_dry_run = false # Set to true to test policies without actual deletion.
}

# IAM binding to allow GKE nodes (via their service account) to pull images.
# This assumes GKE nodes use a service account that needs these permissions.
# If using Workload Identity for pods to pull images, the pod's SA would need this.
# However, GKE nodes themselves (kubelet) need to pull images like pause, metrics agents, etc.,
# and also images for pods if the pod SA doesn't have its own pull secret or WI permission.

# It's common to grant the GKE Node Service Account roles/artifactregistry.reader
# This can be done at the project level or repository level.
# For least privilege, repository level is better.

# We need the GKE node service account email. This would typically be an output from the GKE module
# or a known SA (like the Compute Engine default SA if GKE nodes use that).
# For now, this resource is commented out as it requires an input (GKE node SA email)
# that isn't directly part of this module's variables.

/*
data "google_compute_default_service_account" "gce_default_sa" {
  project = var.gcp_project_id
}

// Alternative: Use a variable for the GKE node service account email
// variable "gke_node_service_account_email" {
//   description = "The service account email used by GKE nodes."
//   type        = string
// }

resource "google_artifact_registry_repository_iam_member" "gke_nodes_can_pull" {
  project    = google_artifact_registry_repository.default.project
  location   = google_artifact_registry_repository.default.location
  repository = google_artifact_registry_repository.default.name # Use .name for the repository_id
  role       = "roles/artifactregistry.reader"
  # member     = "serviceAccount:${var.gke_node_service_account_email}" # If passed as variable
  member     = "serviceAccount:${data.google_compute_default_service_account.gce_default_sa.email}" # If GKE uses GCE default SA
}
*/