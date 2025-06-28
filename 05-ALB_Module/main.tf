locals {
  module_tags = merge(var.tags, {
    terraform_module = "alb"
    environment      = var.environment
  })
  # Use the first domain name for naming resources where a single domain is implied
  primary_domain_name_sanitized = replace(var.domain_names[0], ".", "-")
  lb_base_name                  = "${var.gcp_project_id_prefix}-${var.environment}-${var.load_balancer_name}"

  # Prepare IAP secret versions if IAP is configured for any backend service
  iap_oauth_client_ids = {
    for bs_key, bs_config in var.backend_services_config : bs_key => bs_config.iap_config.oauth2_client_id
    if bs_config.iap_config != null 
  }
  iap_oauth_client_secrets = {
    for bs_key, bs_config in var.backend_services_config : bs_key => bs_config.iap_config.oauth2_client_secret
    if bs_config.iap_config != null 
  }
}

//------------------------------------------------------------------------------
// IP Address
//------------------------------------------------------------------------------
resource "google_compute_global_address" "default" {
  count        = var.create_static_ip && var.ip_address_name == null ? 1 : 0
  project      = var.gcp_project_id
  name         = "${local.lb_base_name}-static-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  description  = "Static IP for ${local.lb_base_name}"
}

data "google_compute_global_address" "existing" {
  count   = var.ip_address_name != null ? 1 : 0
  project = var.gcp_project_id
  name    = var.ip_address_name
}

locals {
  ip_address_self_link = var.ip_address_name != null ? data.google_compute_global_address.existing[0].self_link : (var.create_static_ip ? google_compute_global_address.default[0].self_link : null)
  ip_address           = var.ip_address_name != null ? data.google_compute_global_address.existing[0].address : (var.create_static_ip ? google_compute_global_address.default[0].address : null)
}

//------------------------------------------------------------------------------
// SSL Certificate (Google-managed)
//------------------------------------------------------------------------------
resource "google_compute_managed_ssl_certificate" "default" {
  project     = var.gcp_project_id
  name        = "${local.lb_base_name}-ssl-cert-${local.primary_domain_name_sanitized}"
  description = "Google-managed SSL certificate for ${join(", ", var.domain_names)}"
  managed {
    domains = var.domain_names
  }
}

//------------------------------------------------------------------------------
// Health Checks (one per backend service config)
//------------------------------------------------------------------------------
resource "google_compute_health_check" "default" {
  for_each = {
    for k, v in var.backend_services_config : k => v.health_check_config
    if v.health_check_config.type != "TCP" && v.health_check_config.type != "SSL" # These types use http_health_check
  }

  project     = var.gcp_project_id
  name        = "${local.lb_base_name}-hc-${replace(each.key, "_", "-")}" # each.key is the backend_services_config key
  description = "Health check for ${each.key} backend service"
  timeout_sec = each.value.timeout_sec
  check_interval_sec  = each.value.check_interval_sec
  healthy_threshold   = each.value.healthy_threshold
  unhealthy_threshold = each.value.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = each.value.type == "HTTP" ? [1] : []
    content {
      port_specification = each.value.port != null ? "USE_FIXED_PORT" : "USE_SERVING_PORT"
      port               = each.value.port
      request_path       = each.value.request_path
      proxy_header       = "NONE" # Or PROXY_V1
    }
  }

  dynamic "https_health_check" {
    for_each = each.value.type == "HTTPS" ? [1] : []
    content {
      port_specification = each.value.port != null ? "USE_FIXED_PORT" : "USE_SERVING_PORT"
      port               = each.value.port
      request_path       = each.value.request_path
      proxy_header       = "NONE"
    }
  }

  dynamic "http2_health_check" {
    for_each = each.value.type == "HTTP2" ? [1] : []
    content {
      port_specification = each.value.port != null ? "USE_FIXED_PORT" : "USE_SERVING_PORT"
      port               = each.value.port
      request_path       = each.value.request_path
      proxy_header       = "NONE"
    }
  }
  # Note: google_compute_health_check is for non-regional health checks.
  # For regional LBs or specific use cases, google_compute_region_health_check might be needed.
  # External Application Load Balancers use global health checks.
}

resource "google_compute_health_check" "tcp_ssl_health_checks" {
  for_each = {
    for k, v in var.backend_services_config : k => v.health_check_config
    if v.health_check_config.type == "TCP" || v.health_check_config.type == "SSL"
  }

  project     = var.gcp_project_id
  name        = "${local.lb_base_name}-hc-${replace(each.key, "_", "-")}"
  description = "Health check for ${each.key} backend service (${each.value.type})"
  timeout_sec = each.value.timeout_sec
  check_interval_sec  = each.value.check_interval_sec
  healthy_threshold   = each.value.healthy_threshold
  unhealthy_threshold = each.value.unhealthy_threshold

  dynamic "tcp_health_check" {
    for_each = each.value.type == "TCP" ? [1] : []
    content {
      port_specification = each.value.port != null ? "USE_FIXED_PORT" : "USE_SERVING_PORT"
      port               = each.value.port
      proxy_header       = "NONE"
    }
  }

  dynamic "ssl_health_check" {
    for_each = each.value.type == "SSL" ? [1] : []
    content {
      port_specification = each.value.port != null ? "USE_FIXED_PORT" : "USE_SERVING_PORT"
      port               = each.value.port
      proxy_header       = "NONE"
    }
  }
}

locals {
  # Combine all health checks into a single map for easier lookup
  all_health_checks = merge(
    google_compute_health_check.default,
    google_compute_health_check.tcp_ssl_health_checks
  )
}

//------------------------------------------------------------------------------
// IAP Secret Data Fetching (if IAP is enabled for any backend service)
//------------------------------------------------------------------------------
data "google_secret_manager_secret_version" "iap_oauth_client_ids" {
  for_each = local.iap_oauth_client_ids
  secret   = each.value # Full secret ID path
}

data "google_secret_manager_secret_version" "iap_oauth_client_secrets" {
  for_each = local.iap_oauth_client_secrets
  secret   = each.value # Full secret ID path
}



//------------------------------------------------------------------------------
// Backend Services (one per entry in backend_services_config)
//------------------------------------------------------------------------------
resource "google_compute_backend_service" "default" {
  for_each = var.backend_services_config

  project             = var.gcp_project_id
  name                = "${local.lb_base_name}-bs-${replace(each.key, "_", "-")}" # each.key is the logical name like "frontend-svc"
  description         = each.value.description
  protocol            = upper(each.value.protocol) # HTTP, HTTPS, HTTP2
  port_name           = each.value.port_name
  timeout_sec         = each.value.timeout_sec
  connection_draining_timeout_sec = each.value.connection_draining_timeout_sec
  load_balancing_scheme = "EXTERNAL_MANAGED" # For Global External Application Load Balancer
  health_checks       = [local.all_health_checks[each.key].self_link] # Link to the correct health check

  enable_cdn = each.value.enable_cdn
  dynamic "cdn_policy" {
    for_each = each.value.enable_cdn && each.value.cdn_policy != null ? [each.value.cdn_policy] : []
    content {
      cache_mode              = upper(lookup(cdn_policy.value, "cache_mode", "CACHE_ALL_STATIC"))
      default_ttl             = lookup(cdn_policy.value, "default_ttl", 3600)
      client_ttl              = lookup(cdn_policy.value, "client_ttl", null)
      max_ttl                 = lookup(cdn_policy.value, "max_ttl", null)
      negative_caching        = lookup(cdn_policy.value, "negative_caching", false)
      serve_while_stale       = lookup(cdn_policy.value, "serve_while_stale", null)
      signed_url_cache_max_age_sec = lookup(cdn_policy.value, "signed_url_cache_max_age_sec", null)
      dynamic "negative_caching_policy" {
        for_each = lookup(cdn_policy.value, "negative_caching", false) && lookup(cdn_policy.value, "negative_caching_policy", null) != null ? [lookup(cdn_policy.value, "negative_caching_policy", {})] : []
        content {
          code = negative_caching_policy.value.code # This should be a map in the variable
          ttl  = negative_caching_policy.value.ttl
        }
      }
    }
  }

  dynamic "iap" {
    # for_each = each.value.iap_config != null && each.value.iap_config.enabled ? [1] : []
    for_each = try(each.value.iap_config.enabled, false) ? [1] : []
    content {
      enabled              = true
      oauth2_client_id     = data.google_secret_manager_secret_version.iap_oauth_client_ids[each.key].secret_data
      oauth2_client_secret = data.google_secret_manager_secret_version.iap_oauth_client_secrets[each.key].secret_data
    }
  }

  log_config {
    enable      = lookup(each.value, "log_config_enable", true)
    sample_rate = lookup(each.value, "log_config_sample_rate", 1.0)
  }

  # Attach GKE NEGs to this backend service
  dynamic "backend" {
    for_each = lookup(each.value, "gke_negs", [])
    content {
      group = "zones/${backend.value.zone}/networkEndpointGroups/${backend.value.name}" # Format for Zonal NEGs
      # For Regional NEGs, the format would be:
      # group = "regions/${backend.value.region}/networkEndpointGroups/${backend.value.name}"
      balancing_mode        = "RATE" # Or UTILIZATION, CONNECTION
      max_rate_per_endpoint = 100    # Adjust as needed if using RATE
      capacity_scaler       = 1.0
      description           = "GKE NEG: ${backend.value.name}"
    }
  }

  security_policy = var.security_policy_name # Attach Cloud Armor policy if specified

  depends_on = [
    local.all_health_checks, # Ensure health checks are created first
    data.google_secret_manager_secret_version.iap_oauth_client_ids,
    data.google_secret_manager_secret_version.iap_oauth_client_secrets,
  ]
}

//------------------------------------------------------------------------------
// URL Map
//------------------------------------------------------------------------------
resource "google_compute_url_map" "https_url_map" {
  project         = var.gcp_project_id
  name            = "${local.lb_base_name}-https-url-map"
  description     = "URL map for HTTPS traffic to ${local.lb_base_name}"
  default_service = var.url_map_default_service_backend_key != null ? google_compute_backend_service.default[var.url_map_default_service_backend_key].self_link : null

  dynamic "path_matcher" {
    for_each = var.url_map_path_matchers
    content {
      name            = path_matcher.value.name
      default_service = google_compute_backend_service.default[path_matcher.value.default_service_key].self_link
      description     = path_matcher.value.description
      dynamic "path_rule" {
        for_each = path_matcher.value.path_rules
        content {
          paths   = path_rule.value.paths
          service = google_compute_backend_service.default[path_rule.value.service_key].self_link
          # route_action / url_redirect can be added here if needed
        }
      }
      # header_action can be added here
    }
  }
  # host_rule can be added here for more complex host-based routing
  depends_on = [google_compute_backend_service.default]
}

// URL Map for HTTP to HTTPS Redirect (if enabled)
resource "google_compute_url_map" "http_redirect_url_map" {
  count           = var.enable_http_to_https_redirect ? 1 : 0
  project         = var.gcp_project_id
  name            = "${local.lb_base_name}-http-redirect-url-map"
  description     = "URL map to redirect HTTP to HTTPS for ${local.lb_base_name}"
  default_url_redirect {
    https_redirect         = true
    strip_query            = false # Keep query parameters during redirect
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT" # 301 redirect
  }
}

//------------------------------------------------------------------------------
// Target HTTPS Proxy
//------------------------------------------------------------------------------
resource "google_compute_target_https_proxy" "default" {
  project          = var.gcp_project_id
  name             = "${local.lb_base_name}-https-proxy"
  description      = "HTTPS Target Proxy for ${local.lb_base_name}"
  url_map          = google_compute_url_map.https_url_map.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.default.self_link]
  # ssl_policy     = var.ssl_policy_name # Optional: Attach an SSL Policy
}

//------------------------------------------------------------------------------
// Target HTTP Proxy (for redirect)
//------------------------------------------------------------------------------
resource "google_compute_target_http_proxy" "http_redirect" {
  count       = var.enable_http_to_https_redirect ? 1 : 0
  project     = var.gcp_project_id
  name        = "${local.lb_base_name}-http-redirect-proxy"
  description = "HTTP Target Proxy for redirect on ${local.lb_base_name}"
  url_map     = google_compute_url_map.http_redirect_url_map[0].self_link
}

//------------------------------------------------------------------------------
// Global Forwarding Rule (HTTPS)
//------------------------------------------------------------------------------
resource "google_compute_global_forwarding_rule" "https_default" {
  project               = var.gcp_project_id
  name                  = "${local.lb_base_name}-https-fw-rule"
  description           = "HTTPS Forwarding Rule for ${local.lb_base_name}"
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.self_link
  ip_address            = local.ip_address_self_link # Uses the static or existing IP
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = local.module_tags
}

//------------------------------------------------------------------------------
// Global Forwarding Rule (HTTP for redirect)
//------------------------------------------------------------------------------
resource "google_compute_global_forwarding_rule" "http_redirect" {
  count                 = var.enable_http_to_https_redirect ? 1 : 0
  project               = var.gcp_project_id
  name                  = "${local.lb_base_name}-http-redirect-fw-rule"
  description           = "HTTP Redirect Forwarding Rule for ${local.lb_base_name}"
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http_redirect[0].self_link
  ip_address            = local.ip_address_self_link # Uses the same static or existing IP
  load_balancing_scheme = "EXTERNAL_MANAGED"
  labels                = local.module_tags
}