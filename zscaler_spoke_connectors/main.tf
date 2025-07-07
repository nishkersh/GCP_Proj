# /zscaler_spoke_connectors/main.tf

# Locals for consistent naming
locals {
  resource_suffix = "01"
  total_ac_count  = length(var.zones) * var.ac_count_per_zone
}

# ------------------------------------------------------------------------------
# Data Sources for Existing Spoke VPC and ZPA Credentials
# ------------------------------------------------------------------------------

# Look up the existing Spoke VPC to get its self_link
data "google_compute_network" "spoke_vpc" {
  project = var.project_id
  name    = var.spoke_vpc_name
}

# Fetch ZPA credentials securely from Google Secret Manager
data "google_secret_manager_secret_version" "zpa_credentials" {
  secret = var.zpa_secret_id
}

# The secret payload is expected to be a JSON string. We parse it here.
locals {
  zpa_creds = jsondecode(data.google_secret_manager_secret_version.zpa_credentials.secret_data)
}

# ------------------------------------------------------------------------------
# New Subnet for App Connectors within the Existing Spoke VPC
# ------------------------------------------------------------------------------

resource "google_compute_subnetwork" "ac_subnet" {
  project                  = var.project_id
  name                     = var.ac_subnet_name
  ip_cidr_range            = var.ac_subnet_cidr
  region                   = var.region
  network                  = data.google_compute_network.spoke_vpc.self_link
  private_ip_google_access = true
}

# ------------------------------------------------------------------------------
# ZPA Provider Configuration
# ------------------------------------------------------------------------------

# This provider block is configured within the module to be self-contained.
# It uses the credentials fetched from Secret Manager.
provider "zpa" {
  zpa_client_id     = local.zpa_creds.client_id
  zpa_client_secret = local.zpa_creds.client_secret
  zpa_customer_id   = local.zpa_creds.customer_id
}

# ------------------------------------------------------------------------------
# ZPA App Connector Group and Provisioning Keys
# ------------------------------------------------------------------------------

# This reuses the zpa_app_connector_group module logic from the source material.
module "zpa_app_connector_group" {
  source = "../../modules/terraform-zpa-app-connector-group" # Adjust path as needed

  app_connector_group_name    = "${var.name_prefix}-ac-group-${local.resource_suffix}"
  app_connector_group_enabled = true
  # Using geo-location defaults, can be exposed as variables if needed
  app_connector_group_latitude  = "37.33874"
  app_connector_group_longitude = "-121.8852525"
  app_connector_group_location  = "San Jose, CA, USA"
}

# This reuses the zpa_provisioning_key module logic from the source material.
# We create a unique key for each App Connector VM instance for enhanced security.
module "zpa_provisioning_key" {
  source = "../../modules/terraform-zpa-provisioning-key" # Adjust path as needed

  # Create one key per App Connector VM
  count = local.total_ac_count

  provisioning_key_name             = "${var.name_prefix}-prov-key-${local.resource_suffix}-${count.index}"
  provisioning_key_association_type = "CONNECTOR_GRP"
  provisioning_key_max_usage        = 1 # Each key can only be used once
  app_connector_group_id            = module.zpa_app_connector_group.app_connector_group_id
  enrollment_cert                   = "Connector"
}

# ------------------------------------------------------------------------------
# App Connector VMs (HA Cluster)
# ------------------------------------------------------------------------------

# Find the latest Zscaler App Connector image from the marketplace
data "google_compute_image" "zs_ac_img" {
  project = "mpi-zpa-gcp-marketplace"
  name    = "zpa-connector-rhel-9-20240115" # Note: This might need updating to a newer version over time.
}

# Generate the user_data script for each VM, ensuring each gets its unique provisioning key.
locals {
  ac_user_data = [
    for i in range(local.total_ac_count) : templatefile("${path.module}/user_data.sh.tpl", {
      provisioning_key = module.zpa_provisioning_key[i].provisioning_key
    })
  ]
}

# This reuses the acvm module logic from the source material.
# module "ac_vm" {
#   source = "../../modules/terraform-zsac-acvm-gcp" # Adjust path as needed

#   project             = var.project_id
#   region              = var.region
#   zones               = var.zones
#   name_prefix         = var.name_prefix
#   resource_tag        = local.resource_suffix
#   acvm_instance_type  = var.ac_instance_type
#   ac_count            = var.ac_count_per_zone
#   image_name          = data.google_compute_image.zs_ac_img.self_link
#   acvm_vpc_subnetwork = google_compute_subnetwork.ac_subnet.self_link

#   # Pass the list of generated user_data scripts to the module.
#   # This assumes the module can accept a list of user_data, one for each instance.
#   # If the underlying module does not support this, a custom instance resource loop would be needed.
#   # For this implementation, we assume the module is flexible or we would adapt it.
#   user_data = local.ac_user_data[0] # Simplified for this example; a true HA setup would require module modification or a different loop structure.
#   # A more robust implementation would involve a custom loop creating google_compute_instance resources directly
#   # to assign a unique user_data script to each.
# }

# /zscaler_spoke_connectors/main.tf

# App Connector VMs (HA Cluster) 

# Find the latest Zscaler App Connector image from the marketplace

# gcloud compute images describe-from-family zpa-connector-rhel-9 --project=mpi-zpa-gcp-marketplace
data "google_compute_image" "zs_ac_img" {
  project = "mpi-zpa-gcp-marketplace"
  name    = "zpa-connector-rhel-9" // Note: Image family is used to avoid updating over time .
}

# 1. Create a single instance template for the App Connectors.
#    The user_data will be overridden for each instance.
resource "google_compute_instance_template" "ac_template" {
  project      = var.project_id
  name_prefix  = "${var.name_prefix}-ac-template-"
  machine_type = var.ac_instance_type
  region       = var.region
  tags         = ["spoke-app-connector"]

  disk {
    source_image = data.google_compute_image.zs_ac_img.self_link
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.ac_subnet.self_link
  }

  // This user_data is a placeholder; it will be overridden by per-instance configs.
  metadata = {
    user-data = "# Placeholder"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Create a managed instance group using the template.
resource "google_compute_instance_group_manager" "ac_igm" {
  project            = var.project_id
  name               = "${var.name_prefix}-ac-igm"
  base_instance_name = "${var.name_prefix}-ac-vm"
  zone              = var.zones
  target_size        = local.total_ac_count

  version {
    instance_template = google_compute_instance_template.ac_template.self_link
  }
}

# 3. CRITICAL FIX: Apply a unique user_data script (with its unique provisioning key)
#    to each instance in the managed group.
resource "google_compute_per_instance_config" "ac_instance_config" {
  project                  = var.project_id
  instance_group_manager   = google_compute_instance_group_manager.ac_igm.name
  zone                     = var.zones[floor(count.index / var.ac_count_per_zone)]
  name                     = "${var.name_prefix}-ac-vm-${count.index}"
  count                    = local.total_ac_count

  preserved_state {
    metadata = {
      // Each instance gets its own unique user_data script from the list we generated.
      user-data = local.ac_user_data[count.index]
    }
  }
}
# ------------------------------------------------------------------------------
# Firewall Rules for App Connector Subnet
# ------------------------------------------------------------------------------

# Allow App Connectors to communicate with workloads in the GKE subnet.
# This is a simplified rule; production environments might require more specific ports.
resource "google_compute_firewall" "allow_ac_to_gke" {
  project       = var.project_id
  name          = "${var.spoke_vpc_name}-allow-ac-to-gke"
  network       = data.google_compute_network.spoke_vpc.name
  direction     = "INGRESS"
  source_ranges = [google_compute_subnetwork.ac_subnet.ip_cidr_range]
  # This assumes GKE nodes have a specific network tag.
  # This tag should be applied to the GKE node pools in your '03-GKE_module'.
  target_tags = ["gke-node"]

  allow {
    protocol = "tcp"
    ports    = ["0-65535"] # In production, restrict this to application ports (e.g., 80, 443, 5432)
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }
}

# /zscaler_spoke_connectors/main.tf

# This rule allows SSH access to the Spoke bastion from the App Connectors themselves.
resource "google_compute_firewall" "allow_ac_to_spoke_bastion" {
  project       = var.project_id
  name          = "${var.spoke_vpc_name}-allow-ac-to-bastion"
  network       = data.google_compute_network.spoke_vpc.name
  direction     = "INGRESS"
  source_ranges = [google_compute_subnetwork.ac_subnet.ip_cidr_range]
  // This assumes the Spoke bastion has the tag "spoke-bastion".
  target_tags = ["spoke-bastion"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}