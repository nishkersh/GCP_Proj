# Locals for consistent naming and resource tagging
locals {
  # Suffix for uniqueness, can be customized or replaced with a random_string resource if needed
  resource_suffix = "01"
}

# ------------------------------------------------------------------------------
# Hub VPC Network and Subnets
# ------------------------------------------------------------------------------

resource "google_compute_network" "hub_vpc" {
  project                 = var.project_id
  name                    = var.hub_vpc_name
  auto_create_subnetworks = false
  mtu                     = 1460
}

resource "google_compute_subnetwork" "cc_subnet" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-cc-subnet"
  ip_cidr_range            = var.cc_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.hub_vpc.id
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "mgmt_subnet" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-mgmt-subnet"
  ip_cidr_range            = var.mgmt_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.hub_vpc.id
  private_ip_google_access = true
}

# ------------------------------------------------------------------------------
# NAT Gateway for Private Outbound Access
# ------------------------------------------------------------------------------

resource "google_compute_router" "nat_router" {
  project = var.project_id
  name    = "${var.name_prefix}-nat-router"
  region  = var.region
  network = google_compute_network.hub_vpc.id
}

resource "google_compute_router_nat" "nat_gateway" {
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat-gateway"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.cc_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  subnetwork {
    name                    = google_compute_subnetwork.mgmt_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ------------------------------------------------------------------------------
# Hub Bastion Host (Private IP Only)
# ------------------------------------------------------------------------------

# Note: This bastion is private. Access is via IAP or another bastion in a peered network.
resource "google_compute_instance" "bastion" {
  project      = var.project_id
  zone         = var.zones[0] # Place bastion in the first specified zone
  name         = "${var.name_prefix}-bastion-host"
  machine_type = var.bastion_machine_type
  tags         = ["hub-bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  // This bastion has no public IP. It relies on the NAT Gateway for outbound access.
  network_interface {
    subnetwork = google_compute_subnetwork.mgmt_subnet.id
  }

  metadata = {
    ssh-keys = "admin:${var.bastion_ssh_public_key}"
  }

  // Allow the instance to be stopped for updates, e.g., changing machine type.
  allow_stopping_for_update = true
}

# ------------------------------------------------------------------------------
# IAM Service Account for Cloud Connectors
# ------------------------------------------------------------------------------

# This reuses the iam_service_account module logic from the source material.
module "iam_service_account" {
  source = "../../modules/terraform-zscc-iam-service-account-gcp" # Adjust path as needed

  project                      = var.project_id
  service_account_id           = "${var.name_prefix}-cc-sa-${local.resource_suffix}"
  service_account_display_name = "Zscaler Cloud Connector SA"
  # We are not using BYO or HCP Vault, so other variables use defaults.
}

# ------------------------------------------------------------------------------
# Cloud Connector VMs (HA Cluster)
# ------------------------------------------------------------------------------

# Find the latest Zscaler Cloud Connector image from the marketplace
data "google_compute_image" "zs_cc_img" {
  project = "mpi-zscalercloudconnector-publ"
  name    = "zs-cc-ga-02022025" # Note: This might need updating to a newer version over time.
}

# User data script for bootstrapping the Cloud Connector VMs
locals {
  cc_user_data = jsonencode({
    "cc_url"            = var.cc_vm_prov_url,
    "http_probe_port"   = 50000, # Standard port for ILB health checks
    "gcp_service_account" = module.iam_service_account.service_account,
    "lb_vip"            = module.ilb.ilb_ip_address
  })
}

# This reuses the ccvm module logic from the source material.
module "cc_vm" {
  source = "../../modules/terraform-zscc-ccvm-gcp" # Adjust path as needed

  project                     = var.project_id
  region                      = var.region
  zones                       = var.zones
  name_prefix                 = var.name_prefix
  resource_tag                = local.resource_suffix
  ccvm_instance_type          = var.cc_instance_type
  cc_count                    = var.cc_count_per_zone
  image_name                  = data.google_compute_image.zs_cc_img.self_link
  user_data                   = local.cc_user_data
  service_account             = module.iam_service_account.service_account
  vpc_subnetwork_ccvm_mgmt    = google_compute_subnetwork.mgmt_subnet.self_link
  vpc_subnetwork_ccvm_service = google_compute_subnetwork.cc_subnet.self_link

  # This module does not require SSH keys as management is via the bastion.
}

# ------------------------------------------------------------------------------
# Internal Load Balancer (ILB) for Cloud Connector HA
# ------------------------------------------------------------------------------

# This reuses the ilb module logic from the source material.
module "ilb" {
  source = "../../modules/terraform-zscc-ilb-gcp" # Adjust path as needed

  project                     = var.project_id
  region                      = var.region
  vpc_network                 = google_compute_network.hub_vpc.self_link
  instance_groups             = module.cc_vm.instance_group_ids
  vpc_subnetwork_ccvm_service = google_compute_subnetwork.cc_subnet.self_link
  http_probe_port             = 50000 # Must match the port in user_data

  # Using default names generated by the module based on our prefix
  ilb_backend_service_name = "${var.name_prefix}-cc-backend-service-${local.resource_suffix}"
  ilb_health_check_name    = "${var.name_prefix}-cc-health-check-${local.resource_suffix}"
  ilb_forwarding_rule_name = "${var.name_prefix}-cc-forwarding-rule-${local.resource_suffix}"
}

# ------------------------------------------------------------------------------
# Firewall Rules for Hub VPC
# ------------------------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.hub_vpc_name}-allow-internal"
  network = google_compute_network.hub_vpc.name
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  source_ranges = [
    var.cc_subnet_cidr,
    var.mgmt_subnet_cidr
  ]
}

# Allow IAP to connect to the bastion host for secure, identity-based access
resource "google_compute_firewall" "allow_iap_to_bastion" {
  project       = var.project_id
  name          = "${var.hub_vpc_name}-allow-iap-to-bastion"
  network       = google_compute_network.hub_vpc.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # This is Google's IAP IP range
  target_tags   = ["hub-bastion"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}