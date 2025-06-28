output "instance_name" {
  description = "The name of the Cloud SQL instance."
  value       = google_sql_database_instance.default.name
}

output "instance_connection_name" {
  description = "The connection name of the Cloud SQL instance, used by Cloud SQL Proxy and some libraries (project:region:instance)."
  value       = google_sql_database_instance.default.connection_name
  sensitive   = true
}

output "instance_self_link" {
  description = "The self_link of the Cloud SQL instance."
  value       = google_sql_database_instance.default.self_link
}

output "private_ip_address" {
  description = "The private IP address assigned to the Cloud SQL instance. May take a few minutes to be assigned after creation."
  # The first IP address in the ip_address block is usually the primary one.
  # If private network is enabled, this should be the private IP.
  value       = length(google_sql_database_instance.default.ip_address) > 0 ? google_sql_database_instance.default.ip_address[0].ip_address : "Not yet assigned or private IP not configured"
  sensitive   = true
}

output "public_ip_address" {
  description = "The public IP address assigned to the Cloud SQL instance, if ipv4_enabled and not using private_network exclusively. May take a few minutes to be assigned."
  # This logic attempts to find a PUBLIC IP. If only private IP is used, this might be empty or show the private IP.
  # A more robust way would be to iterate through ip_address and check type, but for a typical setup this is often sufficient.
  value = one([
    for addr in google_sql_database_instance.default.ip_address : addr.ip_address if addr.type == "PRIMARY" && lookup(var.ip_configuration, "private_network_self_link", null) == null
    # If private network is used, the "PRIMARY" IP might be the private one.
    # This output is more relevant if a public IP is expected.
  ]) # The 'one' function expects a single element or null.
  sensitive = true
}

output "database_names" {
  description = "A list of names of the databases created on the instance."
  value       = [for db in google_sql_database.databases : db.name]
}

output "user_name" {
  description = "The name of the default application user created."
  value       = google_sql_user.default_user.name
}

output "instance_first_ip_address" {
  description = "The first IP address listed for the Cloud SQL instance. This is often the primary address clients should use (could be public or private)."
  value       = google_sql_database_instance.default.first_ip_address
  sensitive   = true
}

output "server_ca_cert" {
  description = "The CA certificate for the Cloud SQL instance."
  value       = google_sql_database_instance.default.server_ca_cert[0].cert
  sensitive   = true
}

output "service_account_email_address" {
  description = "The service account email address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.default.service_account_email_address
  sensitive   = true
}