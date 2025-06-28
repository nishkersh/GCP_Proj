provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

//------------------------------------------------------------------------------
// VPC Network
//------------------------------------------------------------------------------
module "vpc" {
  source = "../../01-VPC_module"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  gcp_region            = var.gcp_region
  vpc_name              = var.vpc_name
  auto_create_subnetworks = false # Custom mode VPC

  # subnets = [
  #   for snet_config in var.vpc_subnets : {
  #     name                     = snet_config.name
  #     ip_cidr_range            = snet_config.ip_cidr_range
  #     description              = lookup(snet_config, "description", "Custom subnet for ${snet_config.name}")
  #     private_ip_google_access = lookup(snet_config, "private_ip_google_access", true)
  #     purpose                  = lookup(snet_config, "purpose", null)
  #     log_config = lookup(snet_config, "log_config_enable", false) ? {
  #       aggregation_interval = "INTERVAL_5_SEC"
  #       flow_sampling        = 0.5
  #       metadata             = "INCLUDE_ALL_METADATA"
  #       } : null
  #   }
  # ]
  subnets             = var.vpc_subnets
  secondary_ip_ranges = var.vpc_secondary_ip_ranges

  # Define some basic firewall rules. More specific rules can be added via var.vpc_firewall_rules.
  firewall_rules = concat([
    {
      name        = "allow-internal"
      description = "Allow all internal traffic within the VPC network."
      direction   = "INGRESS"
      priority    = 1000 # Default priority
      source_ranges = [ # Using the primary CIDR ranges of our subnets
        for snet in var.vpc_subnets : snet.ip_cidr_range
      ]
      allow = [{ protocol = "all" }] # Allows all protocols (tcp, udp, icmp)
      # No target_tags means it applies to all instances in the network by default for these source_ranges
    },
    {
      name        = "allow-ssh-iap" # For IAP access to any VM (e.g., GKE nodes if needed for debug)
      description = "Allow SSH via IAP from Google's IAP netblock."
      direction   = "INGRESS"
      source_ranges = ["35.235.240.0/20"] # Google IAP netblock
      allow = [{ protocol = "tcp", ports = ["22"] }]
      # target_tags = ["allow-iap-ssh"] # VMs would need this tag
    },
    {
      name        = "allow-gke-master-to-nodes"
      description = "Allow GKE master to communicate with nodes (health checks, etc.)."
      direction   = "INGRESS"
      source_ranges = [var.gke_master_ipv4_cidr_block] # GKE Master CIDR
      allow = [
        { protocol = "tcp", ports = ["10250", "443"] }, # Kubelet, control plane communication
        { protocol = "udp", ports = ["4789"] }         # VXLAN for Calico if used, or other overlay
      ]
      # target_tags = ["gke-node"] # GKE nodes are typically tagged automatically
    },
    # Egress to internet is allowed by default if no DENY rule blocks it and Cloud NAT is present.
  ], var.vpc_firewall_rules) # Concatenate with any custom rules from variables

  enable_cloud_nat = true # Enable Cloud NAT for private GKE nodes, etc.
  tags             = var.common_tags
}

//------------------------------------------------------------------------------
// Bastion Host
//------------------------------------------------------------------------------
module "bastion" {
  source = "../../02-Bastion_module"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  gcp_region            = var.gcp_region
  zone                  = var.gcp_zone_a # Deploy bastion in zone 'a'

  instance_name = "bastion-host"
  machine_type  = var.bastion_machine_type
  ssh_source_ranges = var.bastion_ssh_source_ranges
  # Assuming 'mgmt-subnet' is defined in var.vpc_subnets
  network_name  = module.vpc.vpc_self_link # Pass the VPC self_link
  subnet_name   = module.vpc.subnet_self_links["mgmt-subnet"] # Pass the mgmt-subnet self_link

  create_static_ip = true

  network_tags      = ["bastion-host", "allow-iap-ssh"] # Tag for its own SSH rule and IAP
  enable_os_login   = true
  startup_script    = "#!/bin/bash\napt-get update -y\napt-get install -y tcpdump dnsutils google-cloud-sdk-gke-gcloud-auth-plugin kubectl\necho 'Bastion setup complete.' > /setup.txt"
  tags              = var.common_tags

  depends_on = [module.vpc]
}

//------------------------------------------------------------------------------
// Google Kubernetes Engine (GKE)
//------------------------------------------------------------------------------
module "gke" {
  source = "../../03-GKE_module"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  gcp_region            = var.gcp_region
  cluster_name          = var.gke_cluster_name
  cluster_deletion_protection = false   # Made it false since in dev enviornment we can delete the cluster at any time

  network_self_link    = module.vpc.vpc_self_link
  subnet_self_link     = module.vpc.subnet_self_links["gke-subnet"]
  pods_ip_range_name   = var.vpc_secondary_ip_ranges["gke-subnet"][0].range_name # Assumes first is pods
  services_ip_range_name = var.vpc_secondary_ip_ranges["gke-subnet"][1].range_name # Assumes second is services

  master_ipv4_cidr_block = var.gke_master_ipv4_cidr_block
  # Dynamically add bastion's public IP to master_authorized_networks if bastion is created
  master_authorized_networks_config = concat(
    var.gke_master_authorized_networks,
    module.bastion.private_ip != null ? [{
      display_name = "bastion-host-access"
      cidr_block   = "${module.bastion.private_ip}/32"
    }] : []
  )

  release_channel             = "STABLE" # Use stable channel for dev
  enable_private_nodes        = true
  enable_private_endpoint     = true
  enable_workload_identity    = true
  enable_shielded_nodes       = true
  enable_vertical_pod_autoscaling = true
  remove_default_node_pool    = true

  node_pools = [
    for np_config in var.gke_node_pools : {
      name                = np_config.name
      machine_type        = lookup(np_config, "machine_type", "e2-medium")
      min_node_count      = lookup(np_config, "min_node_count", 1)
      max_node_count      = lookup(np_config, "max_node_count", 2)
      initial_node_count  = lookup(np_config, "initial_node_count", 1)
      disk_type           = lookup(np_config, "disk_type", "pd-balanced")
      disk_size_gb        = lookup(np_config, "disk_size_gb", 30)
      image_type          = lookup(np_config, "image_type", "COS_CONTAINERD")
      preemptible         = lookup(np_config, "preemptible", false) # For dev, can set to true in tfvars
      spot                = lookup(np_config, "spot", true)        # Use Spot VMs for dev by default
      enable_secure_boot  = true
      enable_integrity_monitoring = true
      oauth_scopes = [
        "https://www.googleapis.com/auth/devstorage.read_only",
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
        "https://www.googleapis.com/auth/servicecontrol",
        "https://www.googleapis.com/auth/service.management.readonly",
        "https://www.googleapis.com/auth/trace.append",
        "https://www.googleapis.com/auth/cloud-platform" # Broader scope for node operations, WI handles app permissions
      ]
      node_labels = lookup(np_config, "node_labels", { "environment" = var.environment, "workload-type" = "general" })
      node_tags   = lookup(np_config, "node_tags", ["gke-${var.gcp_project_id_prefix}-${var.environment}-node"])
      # service_account_email = null # Use default GKE node SA or specify one
    }
  ]
  cluster_resource_labels = { "environment" = var.environment, "cluster" = var.gke_cluster_name }
  tags                    = var.common_tags

  depends_on = [module.vpc, module.bastion]
}


//------------------------------------------------------------------------------
// Cloud SQL for PostgreSQL
//------------------------------------------------------------------------------
module "cloudsql_postgres" {
  source = "../../04-Database_Module"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  gcp_region            = var.gcp_region
  instance_name         = var.db_instance_name
  database_version      = "POSTGRES_15"
  tier                  = var.db_tier
  availability_type     = var.db_availability_type
  disk_size             = var.db_disk_size_gb
  deletion_protection   = false # Easier to tear down dev environments

  ip_configuration = {
    ipv4_enabled             = true
    private_network_self_link = module.vpc.vpc_self_link # Use private IP in the VPC
    require_ssl              = true
    # allocated_ip_range_name = null # Only if using specific reserved range for private services access
  }

  user_name                 = var.db_user_name
  user_password_secret_id   = var.db_user_password_secret_id # Must be provided in tfvars
  databases                 = var.db_databases
  enable_default_user       = false # We create our own app user
  tags                      = var.common_tags

  vpc_private_services_connection = module.vpc.private_services_connection

  depends_on = [
    module.vpc
    # google_service_networking_connection.private_vpc_connection # If managing this explicitly
  ]
}

//------------------------------------------------------------------------------
// Artifact Registry
//------------------------------------------------------------------------------
module "artifact_registry" {
  source = "../../06-GAR"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  gcp_region            = var.gcp_region # Store images in the same region as GKE
  repository_id         = var.ar_repository_id
  immutable_tags        = var.ar_immutable_tags # false for dev, true for prod
  tags                  = var.common_tags
}

//------------------------------------------------------------------------------
// Application Load Balancer (ALB)
//------------------------------------------------------------------------------
module "alb" {
  source = "../../05-ALB_Module"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  load_balancer_name    = var.alb_load_balancer_name
  domain_names          = var.alb_domain_names
  create_static_ip      = true # Create a static IP for dev as well

  backend_services_config = var.alb_backend_services_config # NEGs will be empty initially
  url_map_default_service_backend_key = var.alb_url_map_default_service_backend_key
  url_map_path_matchers   = var.alb_url_map_path_matchers
  tags                    = var.common_tags

  depends_on = [module.gke] # ALB depends on GKE (conceptually, for NEGs)
                           # Actual NEG attachment is a post-GKE-app-deployment step.
}


//------------------------------------------------------------------------------
// CI/CD Infrastructure
//------------------------------------------------------------------------------

// IAM Service Account for Jenkins VM
resource "google_service_account" "jenkins_sa" {
  project      = var.gcp_project_id
  account_id   = "${var.gcp_project_id_prefix}-${var.environment}-jenkins-sa"
  display_name = "Jenkins CI/CD Service Account (${var.environment})"
}

// Grant Jenkins SA permissions
resource "google_project_iam_member" "jenkins_sa_permissions" {
  for_each = toset([
    "roles/artifactregistry.writer", // To push Docker images and Helm charts
    "roles/container.developer",     // To get GKE credentials and interact with cluster
    "roles/secretmanager.secretAccessor" // To access any build-time secrets
  ])
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.jenkins_sa.email}"
}

// Jenkins Master GCE VM
module "jenkins_vm" {
  source = "../../07-jenkins-vm"

  gcp_project_id        = var.gcp_project_id
  gcp_project_id_prefix = var.gcp_project_id_prefix
  environment           = var.environment
  zone                  = var.gcp_zone_a
  subnet_self_link      = module.vpc.subnet_self_links["mgmt-subnet"] // Place in management subnet
  vpc_self_link         = module.vpc.vpc_self_link
  jenkins_service_account_email = google_service_account.jenkins_sa.email

  tags                  = var.common_tags
}

// --- ArgoCD Installation using Helm Provider ---

data "google_client_config" "default" {}


// Kubernetes Provider configuration to talk to the GKE cluster
provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

// Helm Provider configuration
provider "helm" {
  kubernetes = {
    host                   = "https://${module.gke.endpoint}"
    cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

// --- This is the NEW, correct code ---

// Kubernetes Provider configuration using the standard GKE exec plugin
# provider "kubernetes" {
#   host                   = "https://${module.gke.endpoint}"
#   cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "gcloud"
#     args        = ["container", "clusters", "get-credentials", module.gke.cluster_name, "--region", module.gke.location, "--project", var.gcp_project_id, "--internal-ip"]
#   }
# }

# // Helm Provider configuration using the standard GKE exec plugin
# provider "helm" {
#   kubernetes = {
#     host                   = "https://${module.gke.endpoint}"
#     cluster_ca_certificate = base64decode(module.gke.cluster_ca_certificate)
#     exec = {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "gcloud"
#       args        = ["container", "clusters", "get-credentials", module.gke.cluster_name, "--region", module.gke.location, "--project", var.gcp_project_id, "--internal-ip"]
#     }
#   }
# }

// Create namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

// Install ArgoCD using the Helm provider
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.5" 



  depends_on = [
    kubernetes_namespace.argocd,
    module.gke // Ensure GKE cluster is ready
  ]
}



//------------------------------------------------------------------------------
// Application and ArgoCD Configuration
//------------------------------------------------------------------------------

// Create the application namespace
resource "kubernetes_namespace" "app_ns" {
  metadata {
    name = "two-tier-app-dev"
  }
}

// Fetches the database password from Google Secret Manager
data "google_secret_manager_secret_version" "db_password" {
  project = var.gcp_project_id
  secret  = var.db_user_password_secret_id
}

// Creates a native Kubernetes secret with the fetched password
resource "kubernetes_secret" "db_secret" {
  metadata {
    name      = "two-tier-app-db-secret"
    namespace = kubernetes_namespace.app_ns.metadata[0].name
  }
  data = {
    DB_PASSWORD = data.google_secret_manager_secret_version.db_password.secret_data
  }
  type = "Opaque"
}

// Create a repository in Artifact Registry to store Helm charts
resource "google_artifact_registry_repository" "helm_repo" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = "helm-charts"
  description   = "Helm chart repository for CI/CD"
  format        = "DOCKER"
}

// Define the ArgoCD Application using the Kubernetes provider
resource "kubernetes_manifest" "argocd_app" {
  manifest = {
    "apiVersion" = "argoproj.io/v1alpha1"
    "kind"       = "Application"
    "metadata" = {
      "name"      = "two-tier-app-dev"
      "namespace" = "argocd" // The Application CRD must live in the 'argocd' namespace
    }
    "spec" = {
      "project" = "default"
      "source" = {
        "repoURL"        = "https://github.com/nishkersh/Three-tier-App.git" // Your app's Git repo
        "path"           = "helm/two-tier-app" // The path to the Helm chart we will create
        "targetRevision" = "HEAD"
      }
      "destination" = {
        "server"    = "https://kubernetes.default.svc"
        "namespace" = kubernetes_namespace.app_ns.metadata[0].name
      }
      "syncPolicy" = {
        "automated" = {
          "prune"    = true
          "selfHeal" = true
        }
        "syncOptions" = [
          "CreateNamespace=true",
        ]
      }
    }
  }
  depends_on = [helm_release.argocd]
}