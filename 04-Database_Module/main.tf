locals {
  module_tags = merge(var.tags, {
    terraform_module = "cloudsql-postgres"
    environment      = var.environment
  })
  db_instance_full_name = "${var.gcp_project_id_prefix}-${var.environment}-${var.instance_name}"
}

data "google_secret_manager_secret_version" "db_user_password" {
  secret = var.user_password_secret_id # Expects format: projects/PROJECT_ID/secrets/SECRET_NAME/versions/VERSION
}

resource "google_sql_database_instance" "default" {
  project             = var.gcp_project_id
  name                = local.db_instance_full_name
  region              = var.gcp_region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection
  root_password       = var.enable_default_user ? data.google_secret_manager_secret_version.db_user_password.secret_data : null # Only set if default 'postgres' user is enabled and password managed.
   # For the setup, I disabled default user and create a specific one.

  settings {
    tier    = var.tier
    availability_type = var.availability_type
    disk_type         = var.disk_type
    disk_autoresize   = var.disk_autoresize
    disk_autoresize_limit = var.disk_autoresize_limit
    disk_size         = var.disk_size

    backup_configuration {
      enabled                        = lookup(var.backup_configuration, "enabled", true)
      start_time                     = lookup(var.backup_configuration, "start_time", "03:00")
      location                       = lookup(var.backup_configuration, "location", null)
      point_in_time_recovery_enabled = lookup(var.backup_configuration, "point_in_time_recovery_enabled", true)

      transaction_log_retention_days = var.backup_configuration.transaction_log_retention_days
      # binary_log_enabled is implicitly true if point_in_time_recovery_enabled is true for PostgreSQL
      dynamic "backup_retention_settings" {
        for_each = lookup(var.backup_configuration, "point_in_time_recovery_enabled", true) ? [1] : []
        content {
          retained_backups = 7 # Not directly setting number of backups, but enabling PITR implies log retention
          retention_unit   = "COUNT" # This is a bit of a misnomer for PITR logs, but required by provider structure
                                     # Actual log retention is via transaction_log_retention_days if available or implied by PITR.
                                     # For PostgreSQL, PITR relies on WAL archiving.
        }
      }
      # For PostgreSQL, transaction_log_retention_days is not a direct setting in the same way as MySQL.
      # Point-in-time recovery for PostgreSQL relies on continuous archiving of WAL (Write-Ahead Log) files.
      # The retention of these WAL files allows for PITR.
      # The `transaction_log_retention_days` in the variable is more of a conceptual guide here.
    }

    ip_configuration {
      ipv4_enabled     = lookup(var.ip_configuration, "ipv4_enabled", true)
      private_network  = lookup(var.ip_configuration, "private_network_self_link", null)
      ssl_mode      = lookup(var.ip_configuration, "ssl_mode", "ENCRYPTED_ONLY")
      # allocated_ip_range = lookup(var.ip_configuration, "allocated_ip_range_name", null) # Use if  have a pre-allocated range for private services
    }

    maintenance_window {
      day  = var.maintenance_window_day
      hour = var.maintenance_window_hour
    }

    insights_config {
      query_insights_enabled  = lookup(var.insights_config, "query_insights_enabled", true)
      query_string_length     = lookup(var.insights_config, "query_string_length", 1024)
      record_application_tags = lookup(var.insights_config, "record_application_tags", false)
      record_client_address   = lookup(var.insights_config, "record_client_address", false)
    }

    # Database flags can be added here if needed
    # database_flags {
    #   name  = "cloudsql.logical_decoding"
    #   value = "on"
    # }

    activation_policy = var.instance_activation_policy
    user_labels            = local.module_tags
  }

  # Explicitly set root_password to null if default user is disabled,
  # to avoid Terraform trying to set it and failing if the user doesn't exist.
  # This is a common pattern to handle optional password management.
  # However, for PostgreSQL, the 'postgres' user always exists.
  # If var.enable_default_user is false, then password is not managed via Terraform.
  # If true, I would set its password.
  # For this setup, I am not setting the 'postgres' user password via Terraform.
  # The `root_password` argument is for the default 'postgres' user.
  # I will create a separate user.
  # If `var.enable_default_user` is false, I will not attempt to set `root_password`.
  # The ternary operator for `root_password` above handles this.
  # If `var.enable_default_user` is false, `root_password` is null.
  # If `var.enable_default_user` is true, it attempts to use the secret.
  # Since I put default `var.enable_default_user` to false, `root_password` will be null.
  # The 'postgres' user will have a system-generated password initially.

  # Ensure the secret is fetched before trying to use its value
  depends_on = [
    data.google_secret_manager_secret_version.db_user_password,
    # If using a private network, depend on the service networking connection
    # This is typically handled by google_service_networking_connection resource
    # which should be in the VPC module or a dedicated networking module if managing it explicitly.
    # For simplicity here, I will assume the connection is already active or will be handled.
  ]

  lifecycle {
    ignore_changes = [
      # Settings that might be changed by GCP or have complex update paths
      settings[0].disk_size, # If disk_autoresize is true
    ]
  }
}

resource "google_sql_user" "default_user" {
  project    = var.gcp_project_id
  instance   = google_sql_database_instance.default.name
  name       = var.user_name
  password   = data.google_secret_manager_secret_version.db_user_password.secret_data
  # host field is not applicable for Cloud SQL PostgreSQL users in the same way as MySQL.
  # For PostgreSQL, users are global within the instance.
  # type = "BUILT_IN" # For Cloud SQL IAM database authentication, not username/password

  depends_on = [google_sql_database_instance.default]
}

resource "google_sql_database" "databases" {
  for_each = { for db in var.databases : db.name => db }

  project   = var.gcp_project_id
  instance  = google_sql_database_instance.default.name
  name      = each.value.name
  charset   = lookup(each.value, "charset", "UTF8")
  collation = lookup(each.value, "collation", "en_US.UTF8")

  depends_on = [google_sql_database_instance.default]
}

// If using private IP, the google_service_networking_connection resource is crucial.
// It should typically be defined once per VPC network and project.
// If not already managed, it could be part of the VPC module or a foundational setup.

// Example 
/*
resource "google_project_service" "servicenetworking" {
  project = var.gcp_project_id
  service = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_global_address" "private_ip_alloc" {
  project       = var.gcp_project_id
  name          = "${var.gcp_project_id_prefix}-${var.environment}-sql-private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  ip_version    = "IPV4"
  address       = "192.168.250.0" # Example, pick a non-overlapping range
  prefix_length = 24
  network       = var.ip_configuration.private_network_self_link # This should be the VPC self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  project                 = var.gcp_project_id
  network                 = var.ip_configuration.private_network_self_link # VPC self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]
  depends_on              = [google_project_service.servicenetworking]
}

// The Cloud SQL instance would then depend on google_service_networking_connection.private_vpc_connection
// and the ip_configuration.private_network would be the VPC self_link.
// The allocated_ip_range_name in ip_configuration would be google_compute_global_address.private_ip_alloc.name
*/