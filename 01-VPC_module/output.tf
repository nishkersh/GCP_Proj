output "vpc_id" {
  description = "The ID of the VPC network."
  value       = google_compute_network.vpc_network.id
}

output "vpc_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.vpc_network.name
}

output "vpc_self_link" {
  description = "The URI of the VPC network."
  value       = google_compute_network.vpc_network.self_link
}

output "subnets" {
  description = "A map of the created subnets, keyed by their short name."
  value = {
    for k, subnet in google_compute_subnetwork.subnets : k => {
      id                      = subnet.id
      name                    = subnet.name
      self_link               = subnet.self_link
      ip_cidr_range           = subnet.ip_cidr_range
      gateway_address         = subnet.gateway_address
      private_ip_google_access = subnet.private_ip_google_access
      purpose                 = subnet.purpose
      secondary_ip_ranges = [
        for range in subnet.secondary_ip_range : {
          range_name    = range.range_name
          ip_cidr_range = range.ip_cidr_range
        }
      ]
    }
  }
}

output "subnet_self_links" {
  description = "A map of subnet self_links, keyed by their short name (e.g., 'gke-subnet')."
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}

output "subnet_ids" {
  description = "A map of subnet IDs, keyed by their short name."
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.id }
}

output "subnet_names" {
  description = "A map of full subnet names, keyed by their short name."
  value       = { for k, v in google_compute_subnetwork.subnets : k => v.name }
}

output "firewall_rule_names" {
  description = "A list of the names of the created firewall rules."
  value       = [for rule in google_compute_firewall.firewall_rules : rule.name]
}

output "nat_router_name" {
  description = "The name of the Cloud NAT router, if created."
  value       = var.enable_cloud_nat ? google_compute_router.nat_router[0].name : null
}

output "cloud_nat_name" {
  description = "The name of the Cloud NAT gateway, if created."
  value       = var.enable_cloud_nat ? google_compute_router_nat.cloud_nat[0].name : null
}


output "private_services_connection" {
  description = "The private services networking connection for Cloud SQL, etc."
  value       = google_service_networking_connection.private_services_access_connection
}

