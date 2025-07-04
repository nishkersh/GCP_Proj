output "hub_vpc_name" {
  description = "The name of the created Hub VPC."
  value       = google_compute_network.hub_vpc.name
}

output "hub_vpc_self_link" {
  description = "The self-link of the created Hub VPC, used for peering."
  value       = google_compute_network.hub_vpc.self_link
}

output "cloud_connector_ilb_ip" {
  description = "The internal IP address of the Cloud Connector Internal Load Balancer. This is the next-hop IP for traffic routing from Spoke VPCs."
  value       = module.ilb.ilb_ip_address
}

output "bastion_host_name" {
  description = "The name of the private bastion host created in the Hub VPC."
  value       = google_compute_instance.bastion.name
}