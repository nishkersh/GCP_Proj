output "vpc_name" {
  description = "Name of the VPC network."
  value       = module.vpc.vpc_name
}

output "vpc_id" {
  description = "ID of the VPC network."
  value       = module.vpc.vpc_id
}

output "bastion_public_ip" {
  description = "Public IP address of the Bastion host."
  value       = module.bastion.public_ip
  sensitive   = true
}

output "bastion_instance_name" {
  description = "Name of the Bastion host instance."
  value       = module.bastion.instance_name
}

output "gke_cluster_name" {
  description = "Name of the GKE cluster."
  value       = module.gke.cluster_name
}

output "gke_cluster_endpoint" {
  description = "Endpoint of the GKE cluster (private if configured)."
  value       = module.gke.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "Base64 encoded CA certificate for the GKE cluster."
  value       = module.gke.cluster_ca_certificate
  sensitive   = true
}

output "gke_node_pools_names" {
  description = "Names of the GKE node pools."
  value       = module.gke.node_pools_names
}

output "cloudsql_instance_connection_name" {
  description = "Connection name for the Cloud SQL PostgreSQL instance."
  value       = module.cloudsql_postgres.instance_connection_name
  sensitive   = true
}

output "cloudsql_instance_private_ip" {
  description = "Private IP address of the Cloud SQL PostgreSQL instance."
  value       = module.cloudsql_postgres.private_ip_address
  sensitive   = true
}

output "cloudsql_app_user_name" {
  description = "Application database username for Cloud SQL."
  value       = module.cloudsql_postgres.user_name
}

output "cloudsql_app_database_name" {
  description = "Application database name in Cloud SQL."
  value       = length(var.db_databases) > 0 ? var.db_databases[0].name : null # Assuming first db is primary app db
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository for Docker images."
  value       = module.artifact_registry.repository_url
  sensitive   = true
}

output "alb_ip_address" {
  description = "Public IP address of the Application Load Balancer."
  value       = module.alb.load_balancer_ip_address
  sensitive   = true
}

output "alb_domain_names" {
  description = "Domain names configured for the ALB."
  value       = module.alb.ssl_certificate_domains
}