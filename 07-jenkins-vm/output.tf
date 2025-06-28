output "instance_name" {
  value = google_compute_instance.jenkins_master.name
}
output "public_ip" {
  value     = google_compute_instance.jenkins_master.network_interface[0].access_config[0].nat_ip
  sensitive = true
}