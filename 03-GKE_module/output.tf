output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.primary.name
}

output "cluster_id" {
  description = "The ID of the GKE cluster."
  value       = google_container_cluster.primary.id
}

output "cluster_self_link" {
  description = "The self_link of the GKE cluster."
  value       = google_container_cluster.primary.self_link
}

output "location" {
  description = "The location (region) of the GKE cluster."
  value       = google_container_cluster.primary.location
}

output "endpoint" {
  description = "The IP address of the GKE cluster master endpoint."
  value       = google_container_cluster.primary.endpoint
  sensitive   = true # The endpoint might be private
}

output "private_endpoint" {
  description = "The private IP address of the GKE cluster master endpoint (if private endpoint is enabled)."
  value       = google_container_cluster.primary.private_cluster_config[0].private_endpoint # private_cluster_config is a list
  sensitive   = true
}

output "public_endpoint" {
  description = "The public IP address of the GKE cluster master endpoint (if private endpoint is disabled or global access is enabled)."
  value       = google_container_cluster.primary.private_cluster_config[0].public_endpoint # private_cluster_config is a list
  sensitive   = true
}

output "master_version" {
  description = "The current Kubernetes master version of the GKE cluster."
  value       = google_container_cluster.primary.master_version
}

output "node_pools_names" {
  description = "A list of names of the GKE node pools created."
  value       = [for pool in google_container_node_pool.pools : pool.name]
}

output "node_pools_versions" {
  description = "A map of node pool names to their current Kubernetes node versions."
  value = {
    for name, pool in google_container_node_pool.pools : name => pool.version
  }
}

output "workload_identity_pool" {
  description = "The Workload Identity Pool name for the cluster (e.g., PROJECT_ID.svc.id.goog)."
  value       = google_container_cluster.primary.workload_identity_config[0].workload_pool # workload_identity_config is a list
}

output "cluster_ca_certificate" {
  description = "The cluster CA certificate (base64 encoded)."
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate # master_auth is a list
  sensitive   = true
}

# Service account used by the GKE control plane (not nodes)
# output "gke_cluster_service_account_email" {
#   description = "The service account email used by the GKE control plane."
#   # The actual service account used by the control plane might be Google-managed if not specified.
#   # This output reflects the `service_account` field in `node_config` at the cluster level.
#   value       = google_container_cluster.primary.node_config[0].service_account # node_config is a list
# }

# Default service account used by nodes if not overridden per node pool
output "default_node_pool_service_account_email" {
  description = "The default service account email used by GKE nodes if not overridden in a specific node pool."
  value       = local.node_service_account
}