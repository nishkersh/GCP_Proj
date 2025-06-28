output "load_balancer_ip_address" {
  description = "The public IP address of the Application Load Balancer."
  value       = local.ip_address
  sensitive   = true
}

output "load_balancer_name_prefix" {
  description = "The base name used for the load balancer resources."
  value       = local.lb_base_name
}

output "https_forwarding_rule_name" {
  description = "The name of the HTTPS global forwarding rule."
  value       = google_compute_global_forwarding_rule.https_default.name
}

output "https_forwarding_rule_self_link" {
  description = "The self_link of the HTTPS global forwarding rule."
  value       = google_compute_global_forwarding_rule.https_default.self_link
}

output "http_redirect_forwarding_rule_name" {
  description = "The name of the HTTP redirect global forwarding rule, if created."
  value       = var.enable_http_to_https_redirect ? google_compute_global_forwarding_rule.http_redirect[0].name : null
}

output "https_target_proxy_name" {
  description = "The name of the Target HTTPS Proxy."
  value       = google_compute_target_https_proxy.default.name
}

output "http_redirect_target_proxy_name" {
  description = "The name of the Target HTTP Proxy for redirects, if created."
  value       = var.enable_http_to_https_redirect ? google_compute_target_http_proxy.http_redirect[0].name : null
}

output "https_url_map_name" {
  description = "The name of the URL map used for HTTPS traffic."
  value       = google_compute_url_map.https_url_map.name
}

output "http_redirect_url_map_name" {
  description = "The name of the URL map used for HTTP to HTTPS redirection, if created."
  value       = var.enable_http_to_https_redirect ? google_compute_url_map.http_redirect_url_map[0].name : null
}

output "ssl_certificate_name" {
  description = "The name of the Google-managed SSL certificate."
  value       = google_compute_managed_ssl_certificate.default.name
}

output "ssl_certificate_domains" {
  description = "The list of domains covered by the Google-managed SSL certificate."
  value       = google_compute_managed_ssl_certificate.default.managed[0].domains
}

# output "ssl_certificate_status" {
#   description = "The status of the Google-managed SSL certificate (e.g., PROVISIONING, ACTIVE). May take time to become ACTIVE."
#   # Note: This status might not be immediately ACTIVE after terraform apply.
#   # DNS propagation and domain verification by Google can take time.
#   value       = google_compute_managed_ssl_certificate.default.managed[0].status
# }

output "backend_service_names" {
  description = "A map of logical backend service keys to their created names."
  value = {
    for k, bs in google_compute_backend_service.default : k => bs.name
  }
}

output "backend_service_self_links" {
  description = "A map of logical backend service keys to their self_links."
  value = {
    for k, bs in google_compute_backend_service.default : k => bs.self_link
  }
}

output "health_check_names" {
  description = "A map of logical backend service keys to their associated health check names."
  value = {
    for k, hc in local.all_health_checks : k => hc.name
  }
}