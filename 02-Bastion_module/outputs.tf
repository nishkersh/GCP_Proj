output "instance_name" {
  description = "The name of the bastion host instance."
  value       = google_compute_instance.bastion_host.name
}

output "instance_id" {
  description = "The ID of the bastion host instance."
  value       = google_compute_instance.bastion_host.id
}

output "instance_self_link" {
  description = "The self_link of the bastion host instance."
  value       = google_compute_instance.bastion_host.self_link
}

output "network_tags" {
  description = "The network tags applied to the bastion host."
  value       = google_compute_instance.bastion_host.tags
}

output "public_ip" {
  description = "The public IP address of the bastion host, if one was created."
  value       = var.create_external_ip ? google_compute_address.static_ip[0].address : null
  sensitive = true
}

output "private_ip" {
  description = "The private IP address of the bastion host."
  value       = google_compute_instance.bastion_host.network_interface[0].network_ip
}

output "zone" {
  description = "The zone where the bastion host is located."
  value       = google_compute_instance.bastion_host.zone
}

# output "service_account_email" {
#   description = "The email of the service account attached to the bastion host."
#   value       = google_compute_instance.bastion_host.service_account[0].email # service_account is a list, take the first
# }

output "ssh_firewall_rule_name" {
  description = "The name of the firewall rule allowing direct SSH access to the bastion."
  value       = google_compute_firewall.allow_ssh_to_bastion.name
}

output "iap_ssh_firewall_rule_name" {
  description = "The name of the firewall rule allowing IAP SSH access to the bastion."
  value       = google_compute_firewall.allow_iap_ssh_to_bastion.name
}