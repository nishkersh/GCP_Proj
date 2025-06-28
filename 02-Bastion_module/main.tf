locals {
  module_tags = merge(var.tags, {
    terraform_module = "bastion"
    environment      = var.environment
    role             = "bastion-host"
  })
  bastion_full_name = "${var.gcp_project_id_prefix}-${var.environment}-${var.instance_name}"

  network_self_link = var.network_name # Expecting self_link like projects/PROJECT_ID/global/networks/VPC_NAME
  subnet_self_link  = var.subnet_name  # Expecting self_link like projects/PROJECT_ID/regions/REGION/subnetworks/SUBNET_NAME
}


resource "google_compute_address" "static_ip" {
  count   = var.create_static_ip ? 1 : 0
  project = var.gcp_project_id
  name    = "${local.bastion_full_name}-static-ip"
  region  = var.gcp_region
}

resource "google_compute_instance" "bastion_host" {
  project              = var.gcp_project_id
  zone                 = var.zone
  name                 = local.bastion_full_name
  machine_type         = var.machine_type
  deletion_protection  = var.deletion_protection

  tags = concat(var.network_tags, ["ssh-iap-allowed"]) # "ssh-iap-allowed" tag can be used for IAP firewall rule

  boot_disk {
    initialize_params {
      image = var.boot_disk_image
      type  = var.boot_disk_type
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    subnetwork = local.subnet_self_link # Use the subnet self_link

    dynamic "access_config" {
      for_each = var.create_external_ip ? [1] : []
      content {
        
        nat_ip = var.create_static_ip ? google_compute_address.static_ip[0].address : null
      }
    }
  }

  metadata = {
    "enable-oslogin" = var.enable_os_login ? "TRUE" : "FALSE"
    "startup-script" = var.startup_script != null ? var.startup_script : ""
  }

  service_account {
    email  = var.service_account_email # Can be null to use default GCE SA
    scopes = var.service_account_email != null ? var.service_account_scopes : []
  }

  shielded_instance_config {
    enable_secure_boot          = var.shielded_instance_config.enable_secure_boot
    enable_vtpm                 = var.shielded_instance_config.enable_vtpm
    enable_integrity_monitoring = var.shielded_instance_config.enable_integrity_monitoring
  }

  labels = local.module_tags

  lifecycle {
    ignore_changes = [
      # If startup scripts are used for one-time setup,
      # their content might change on the instance post-creation.
      # metadata["startup-script"],
    ]
  }

  allow_stopping_for_update = true # Allows modifying certain instance attributes like machine_type or SA by stopping/starting
}

// Firewall rule specifically for SSH to the bastion host
// This rule is created by the bastion module itself for clarity,
// alternatively, it could be part of the VPC module's firewall rules input.
resource "google_compute_firewall" "allow_ssh_to_bastion" {
  project       = var.gcp_project_id
  name          = "${local.bastion_full_name}-allow-ssh"
  network       = local.network_self_link # Use the network self_link
  direction     = "INGRESS"
  priority      = 1000
  description   = "Allow SSH access to bastion hosts from specified source ranges."

  # source_ranges = ["35.235.240.0/20"]
  source_ranges = var.ssh_source_ranges

  target_tags   = var.network_tags # Apply to instances with tags like "bastion"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA" # Enable logging for this firewall rule
  }
}

// Firewall rule to allow IAP for SSH to instances tagged with "ssh-iap-allowed"
// IAP (Identity-Aware Proxy) provides a more secure way to SSH without exposing bastion to public internet.
// This is a good practice to enable.
resource "google_compute_firewall" "allow_iap_ssh_to_bastion" {
  project       = var.gcp_project_id
  name          = "${local.bastion_full_name}-allow-iap-ssh"
  network       = local.network_self_link
  direction     = "INGRESS"
  priority      = 1000
  description   = "Allow SSH via IAP to bastion hosts."

  # IAP's TCP forwarding uses this specific IP range.
  # Reffrence: https://cloud.google.com/iap/docs/using-tcp-forwarding
  
  source_ranges = ["35.235.240.0/20"] // IAP range is 35.235.240.0/20
  target_tags   = ["ssh-iap-allowed"] # Apply to instances with this tag

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}