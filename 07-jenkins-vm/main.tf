locals {
  instance_name = "${var.gcp_project_id_prefix}-${var.environment}-jenkins-master"
  network_tags  = ["jenkins-master", "allow-ssh", "allow-jenkins-ui"]
}

resource "google_compute_instance" "jenkins_master" {
  project      = var.gcp_project_id
  zone         = var.zone
  name         = local.instance_name
  machine_type = var.machine_type
  tags         = local.network_tags
  labels       = var.tags

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_self_link
    access_config {
      // Ephemeral external IP
    }
  }

  service_account {
    email  = var.jenkins_service_account_email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    "startup-script" = file("${path.module}/startup.sh")
  }

  allow_stopping_for_update = true
}

resource "google_compute_firewall" "allow_ssh" {
  project       = var.gcp_project_id
  name          = "${local.instance_name}-allow-ssh"
  network       = var.vpc_self_link
  # source_ranges = ["35.235.240.0/20"]
  source_ranges = var.jenkins_ssh_source_ranges
  target_tags   = ["allow-ssh"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_jenkins_ui" {
  project       = var.gcp_project_id
  name          = "${local.instance_name}-allow-ui"
  network       = var.vpc_self_link
  # source_ranges = ["35.235.240.0/20"]
  source_ranges = var.jenkins_http_source_ranges
  target_tags   = ["allow-jenkins-ui"]
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
}

