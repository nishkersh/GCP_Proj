locals {
  module_tags = merge(var.tags, {
    terraform_module = "gke"
    environment      = var.environment
  })
  gke_full_name = "${var.gcp_project_id_prefix}-${var.environment}-${var.cluster_name}"

  # Construct Workload Identity namespace if not provided
  workload_identity_namespace = var.identity_namespace != "" ? var.identity_namespace : "${var.gcp_project_id}.svc.id.goog"

  # Determine Kubernetes versioning based on release channel
  release_channel_config = var.release_channel != "UNSPECIFIED" ? {
    channel = upper(var.release_channel)
    } : null # If UNSPECIFIED, don't set release_channel block, rely on min_master_version or initial_cluster_version

  # For non-channel mode, set min_master_version. For channel mode, GKE manages this.
  # Provider version 6.35.0 uses `min_master_version` and `node_version` for node pools.
  # Newer providers might use `kubernetes_version` at the cluster level and allow node pools to inherit or override.
  # I will set min_master_version if not using a channel.
  min_master_version_config = var.release_channel == "UNSPECIFIED" ? var.kubernetes_version : null

  # Node pool service account: Use provided or default Compute Engine SA
  # This is the SA for the nodes themselves, not for Workload Identity.
  node_service_account = var.gke_node_service_account_email == null ? data.google_compute_default_service_account.default[0].email : var.gke_node_service_account_email
}

data "google_compute_default_service_account" "default" {
  count      = var.gke_node_service_account_email == null ? 1 : 0
  project    = var.gcp_project_id
}

resource "google_container_cluster" "primary" {
  project    = var.gcp_project_id
  name       = local.gke_full_name
  location   = var.gcp_region # For regional clusters, location is the region
  resource_labels      = merge(local.module_tags, var.cluster_resource_labels)

   deletion_protection = var.cluster_deletion_protection

  # Networking
  network    = var.network_self_link
  subnetwork = var.subnet_self_link
  networking_mode = "VPC_NATIVE" # Required for VPC-native clusters (using alias IPs)

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_ip_range_name
    services_secondary_range_name = var.services_ip_range_name
  }

  private_cluster_config {
    enable_private_nodes    = var.enable_private_nodes
    # public_endpoint  = var.gke_enable_public_endpoint
    enable_private_endpoint = var.enable_private_endpoint
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    # master_global_access_config { enabled = false } # If true, allows global access to private master, typically false
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks_config
      content {
        display_name = cidr_blocks.value.display_name
        cidr_block   = cidr_blocks.value.cidr_block
      }
    }
  }

  # Versioning
  # For provider 6.35.0, if release_channel is set, min_master_version should not be set.
  # If release_channel is UNSPECIFIED, min_master_version should be set.
  min_master_version = local.min_master_version_config # Set only if not using a release channel
  dynamic "release_channel" {
    for_each = local.release_channel_config != null ? [local.release_channel_config] : []
    content {
      channel = release_channel.value.channel
    }
  }

  # Node Pools Management
  remove_default_node_pool = var.remove_default_node_pool
  initial_node_count       = var.remove_default_node_pool ? 1 : var.default_pool_initial_node_count 
  # If true, must be >= 1.
  # If false, use a variable for desired default pool size.


  # Features
  workload_identity_config {
    workload_pool = local.workload_identity_namespace
  }

  
  enable_shielded_nodes = var.enable_shielded_nodes
  

  vertical_pod_autoscaling {
    enabled = var.enable_vertical_pod_autoscaling
  }

  addons_config {
    http_load_balancing {
      disabled = !var.enable_http_load_balancing
    }
    # Other addons like NetworkPolicyConfig, GcePersistentDiskCsiDriverConfig can be configured here
    # Example:
    # network_policy_config {
    #   disabled = false # Enable network policies
    # }
    # gcp_filestore_csi_driver_config {
    #   enabled = true
    # }
  }

  # Security
  database_encryption {
    state    = var.database_encryption_key_name == null ? "DECRYPTED" : "ENCRYPTED" # This seems counter-intuitive.
                                                                                    # "DECRYPTED" means Google-managed keys.
                                                                                    # "ENCRYPTED" means CMEK.
    key_name = var.database_encryption_key_name
  }

  # Maintenance Policy
  # dynamic "maintenance_policy" {
  #   for_each = var.maintenance_policy_recurrence != null ? [1] : []
  #   content {
  #     recurring_window {
  #       start_time = var.maintenance_policy_start_time
  #       end_time   = var.maintenance_policy_end_time
  #       recurrence = var.maintenance_policy_recurrence
  #       # start_time and end_time can also be specified if needed
  #     }
  #   }
  # }

  # Service Account for GKE Control Plane (not nodes)
  


  # Logging and Monitoring
  logging_service    = "logging.googleapis.com/kubernetes" # Enables GKE-specific logging
  monitoring_service = "monitoring.googleapis.com/kubernetes" # Enables GKE-specific monitoring

  # Other settings
  default_max_pods_per_node = 50 # Default, can be adjusted based on IP availability and density needs
  enable_tpu                  = false # Enable if TPUs needed
  enable_legacy_abac          = false # Legacy ABAC should be disabled

  # Ensure node pools are created after the cluster, especially if removing default.
  # This explicit dependency isn't strictly necessary if node pools reference cluster.id,
  # but can make behavior more predictable in some edge cases.
  # depends_on = [] # Usually not needed here, node pools will depend on this cluster.

  lifecycle {
    ignore_changes = [
      # If not using release channels, GKE might auto-upgrade patch versions.
      # min_master_version,
      # If using release channels, GKE manages node versions too.
      # node_pool.node_config.guest_accelerator, # Avoid issues if not explicitly managing GPUs/TPUs
    ]
  }
}

resource "google_container_node_pool" "pools" {
  for_each = { for pool in var.node_pools : pool.name => pool }

  project    = var.gcp_project_id
  name       = each.value.name
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name # Reference the created cluster by name

  # Versioning - Nodes should ideally match master or be compatible
  # If using release channels, GKE manages node versions.
  # If not,  might need to set 'version' here, often to google_container_cluster.primary.min_master_version
  # or google_container_cluster.primary.current_master_version.
  # For provider 6.35.0, 'version' is the attribute.
  version = var.release_channel == "UNSPECIFIED" ? var.kubernetes_version : null # Set explicitly if not using channel, else let GKE manage.

  initial_node_count = lookup(each.value, "initial_node_count", 1) # Per zone for regional
  # node_count         = lookup(each.value, "initial_node_count", null) == null ? lookup(each.value, "min_node_count", 1) : null 
  # Set node_count if initial_node_count is not set, for non-autoscaling pools.

  autoscaling {
    min_node_count = lookup(each.value, "min_node_count", 1)
    max_node_count = lookup(each.value, "max_node_count", 3)
    # location_policy = "BALANCED" # or "ANY" for regional clusters
  }

  management {
    auto_repair  = true
    auto_upgrade = true # Recommended, especially if using release channels
  }

  node_config {
    machine_type = lookup(each.value, "machine_type", "e2-medium")
    disk_type    = lookup(each.value, "disk_type", "pd-balanced")
    disk_size_gb = lookup(each.value, "disk_size_gb", 50)
    image_type   = upper(lookup(each.value, "image_type", "COS_CONTAINERD"))

    preemptible = lookup(each.value, "preemptible", false)
    spot        = lookup(each.value, "spot", false)

    # Service account for the nodes.
    # For Workload Identity, applications get their own identity.
    # This SA is for node-level operations (kubelet, log shipping, metrics).
    # Using the project's default Compute Engine SA is common if not specifying a custom one.
    service_account = lookup(each.value, "service_account_email", local.node_service_account)
    oauth_scopes    = lookup(each.value, "oauth_scopes", [
      "https://www.googleapis.com/auth/cloud-platform"
    ])

    labels = merge(
      local.module_tags, # Add common module tags
      { "gcp-nodepool" = each.value.name }, # Identify the nodepool
      lookup(each.value, "node_labels", {})
    )
    tags = concat(
      ["gke-node", "${local.gke_full_name}-node", each.value.name], # Basic tags
      lookup(each.value, "node_tags", [])
    )

    shielded_instance_config {
      enable_secure_boot          = var.enable_shielded_nodes && lookup(each.value, "enable_secure_boot", true)
      enable_integrity_monitoring = var.enable_shielded_nodes && lookup(each.value, "enable_integrity_monitoring", true)
    }

    # metadata = {
    #   "disable-legacy-endpoints" = "true"
    # }
  }

  # For regional clusters, specify node locations (zones within the region)
  # If not specified, GKE will pick zones. For better control, you can list them.
  # node_locations = [
  #   "${var.gcp_region}-a",
  #   "${var.gcp_region}-b",
  #   "${var.gcp_region}-c",
  # ]

  lifecycle {
    ignore_changes = [
      # If auto_upgrade is true, GKE might change the version.
      # version,
      # initial_node_count, # After creation, autoscaling takes over.
    ]
    create_before_destroy = true # For node pool updates, create new nodes before deleting old ones.
  }

  depends_on = [google_container_cluster.primary]
}