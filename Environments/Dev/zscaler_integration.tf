# /Environments/Dev/zscaler_integration.tf

# ------------------------------------------------------------------------------
# Zscaler Hub and Spoke Deployment
# ------------------------------------------------------------------------------

# This module creates the new Hub VPC and deploys the Cloud Connector HA cluster.
module "zscaler_hub" {
  source = "../../zscaler_hub" # Assumes new module is at the root

  project_id         = var.gcp_project_id
  region             = var.gcp_region
  zones              = [var.gcp_zone_a, var.gcp_zone_b] # Example for HA
  name_prefix        = "zs-hub-dev"
  hub_vpc_name       = "zs-hub-vpc-dev"
  cc_subnet_cidr     = "10.200.0.0/24"
  mgmt_subnet_cidr   = "10.200.1.0/24"
  cc_vm_prov_url     = var.zs_cc_prov_url # Assumes this is added to variables.tf
  cc_count_per_zone  = 1
  bastion_ssh_public_key = var.ssh_public_key # Assumes this is added to variables.tf
}

# This module deploys the App Connector HA cluster into our existing Spoke VPC.
module "zscaler_spoke_connectors" {
  source = "../../zscaler_spoke_connectors" # Assumes new module is at the root

  project_id      = var.gcp_project_id
  region          = var.gcp_region
  zones           = [var.gcp_zone_a, var.gcp_zone_b] # Example for HA
  name_prefix     = "zs-spoke-dev"
  spoke_vpc_name  = module.vpc.vpc_name # Reference our existing Spoke VPC
  ac_subnet_name  = "zs-ac-subnet-dev"
  ac_subnet_cidr  = "10.10.18.0/24" # New subnet CIDR within existing Spoke VPC range
  ac_count_per_zone = 1
  zpa_secret_id   = var.zpa_secret_id # Assumes this is added to variables.tf
}

# ------------------------------------------------------------------------------
# Hub and Spoke VPC Peering
# ------------------------------------------------------------------------------

# Peer the Spoke VPC to the Hub VPC
resource "google_compute_network_peering" "spoke_to_hub" {
  name         = "peer-spoke-to-hub-dev"
  network      = module.vpc.vpc_self_link # Our existing Spoke VPC
  peer_network = module.zscaler_hub.hub_vpc_self_link
}

# Peer the Hub VPC back to the Spoke VPC
resource "google_compute_network_peering" "hub_to_spoke" {
  name         = "peer-hub-to-spoke-dev"
  network      = module.zscaler_hub.hub_vpc_self_link
  peer_network = module.vpc.vpc_self_link # Our existing Spoke VPC
}

# ------------------------------------------------------------------------------
# Spoke VPC Default Route to Zscaler Cloud Connector
# ------------------------------------------------------------------------------

# Create a default route in the Spoke VPC to send all internet-bound traffic
# to the Cloud Connector ILB in the Hub VPC.
resource "google_compute_route" "spoke_default_route_to_hub_ilb" {
  project      = var.gcp_project_id
  name         = "spoke-default-route-to-zs-hub-dev"
  dest_range   = "0.0.0.0/0"
  network      = module.vpc.vpc_name
  next_hop_ilb = module.zscaler_hub.cloud_connector_ilb_ip
  priority     = 800 # Lower number = higher priority. Should be higher than default internet gateway.

  depends_on = [google_compute_network_peering.spoke_to_hub]
}