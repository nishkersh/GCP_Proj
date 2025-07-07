# /zscaler_spoke_connectors/outputs.tf

output "app_connector_group_id" {
  description = "The ID of the ZPA App Connector Group created for this Spoke."
  value       = module.zpa_app_connector_group.app_connector_group_id
}

output "app_connector_subnet_name" {
  description = "The name of the subnet created for the App Connectors."
  value       = google_compute_subnetwork.ac_subnet.name
}

# /zscaler_spoke_connectors/outputs.tf

output "app_connector_subnet_cidr" {
  description = "The CIDR range of the subnet created for the App Connectors."
  value       = google_compute_subnetwork.ac_subnet.ip_cidr_range
}