locals {
  module_tags = merge(var.tags, {
    terraform_module = "vpc"
    environment      = var.environment
  })
  vpc_full_name = "${var.gcp_project_id_prefix}-${var.environment}-${var.vpc_name}" 
}

resource "google_compute_network" "vpc_network" {
  project                         = var.gcp_project_id
  name                            = local.vpc_full_name
  auto_create_subnetworks         = var.auto_create_subnetworks
  routing_mode                    = var.routing_mode
  mtu                             = var.mtu
  delete_default_routes_on_create = var.delete_default_routes_on_create

  lifecycle {
    prevent_destroy = true # Safety measure to prevent accidental deletion of the VPC
  }
}

resource "google_compute_subnetwork" "subnets" {
  for_each = { for subnet in var.subnets : subnet.name => subnet }

  project                  = var.gcp_project_id
  name                     = "${local.vpc_full_name}-${each.value.name}"
  ip_cidr_range            = each.value.ip_cidr_range
  region                   = var.gcp_region
  network                  = google_compute_network.vpc_network.id
  description              = each.value.description
  private_ip_google_access = each.value.private_ip_google_access
  purpose                  = each.value.purpose
  role                     = each.value.role
  stack_type               = each.value.stack_type

  dynamic "log_config" {
    for_each = each.value.log_config != null ? [each.value.log_config] : []
    content {
      aggregation_interval = log_config.value.aggregation_interval
      flow_sampling        = log_config.value.flow_sampling
      metadata             = log_config.value.metadata
    }
  }

  dynamic "secondary_ip_range" {
    for_each = lookup(var.secondary_ip_ranges, each.key, [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_firewall" "firewall_rules" {
  for_each = { for rule in var.firewall_rules : rule.name => rule }

  project     = var.gcp_project_id
  name        = "${local.vpc_full_name}-fw-${each.value.name}"
  network     = google_compute_network.vpc_network.id
  description = each.value.description
  direction   = upper(each.value.direction)
  priority    = each.value.priority
  disabled    = each.value.disabled

  source_ranges           = length(each.value.source_ranges) > 0 ? each.value.source_ranges : null
  source_tags             = length(each.value.source_tags) > 0 ? each.value.source_tags : null
  source_service_accounts = length(each.value.source_service_accounts) > 0 ? each.value.source_service_accounts : null
  target_tags             = length(each.value.target_tags) > 0 ? each.value.target_tags : null
  target_service_accounts = length(each.value.target_service_accounts) > 0 ? each.value.target_service_accounts : null

  dynamic "log_config" {
    for_each = each.value.log_config != null ? [each.value.log_config] : []
    content {
      metadata = log_config.value.metadata
    }
  }

  dynamic "allow" {
    for_each = each.value.allow
    content {
      protocol = lower(allow.value.protocol)
      ports    = allow.value.ports
    }
  }

  dynamic "deny" {
    for_each = each.value.deny
    content {
      protocol = lower(deny.value.protocol)
      ports    = deny.value.ports
    }
  }

  depends_on = [google_compute_network.vpc_network]
}

// Cloud NAT Configuration (Optional)
resource "google_compute_router" "nat_router" {
  count   = var.enable_cloud_nat ? 1 : 0
  project = var.gcp_project_id
  name    = "${local.vpc_full_name}-nat-router"
  region  = var.gcp_region
  network = google_compute_network.vpc_network.id

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_router_nat" "cloud_nat" {
  count   = var.enable_cloud_nat ? 1 : 0
  project = var.gcp_project_id
  name    = "${local.vpc_full_name}-cloud-nat"
  router  = google_compute_router.nat_router[0].name
  region  = var.gcp_region

  nat_ip_allocate_option = var.nat_ip_allocate_option
  source_subnetwork_ip_ranges_to_nat = var.nat_source_subnetwork_ip_ranges_to_nat

  # If using LIST_OF_SUBNETWORKS, I have to configure subnetwork blocks here
  # But for this  this setup I have used ALL_SUBNETWORKS_ALL_IP_RANGES or similar,
  # so explicit subnetwork blocks are not needed unless that var changes.

  log_config {
    enable = var.log_config_enable_cloud_nat
    filter = var.log_config_filter_cloud_nat
  }

  depends_on = [google_compute_router.nat_router]
}


# ------------------------------------------------------------------------------
# Private Services Access for Cloud SQL, etc.
# ------------------------------------------------------------------------------

resource "google_compute_global_address" "private_services_access_range" {
  project       = var.gcp_project_id
  name          = "${local.vpc_full_name}-private-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16 # A /16 range is standard for this
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_services_access_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_access_range.name]

  depends_on = [google_compute_global_address.private_services_access_range]
}