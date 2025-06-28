// --- Application Configuration ---
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = var.app_namespace
    labels    = var.app_labels
  }
  data = {
    DB_HOST = var.db_host
    DB_PORT = var.db_port
  }
}

// --- Application Deployment ---
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "${var.app_name}-deployment"
    namespace = var.app_namespace
    labels    = var.app_labels
  }
  spec {
    replicas = var.app_replicas
    selector {
      match_labels = var.app_labels
    }
    template {
      metadata {
        labels = var.app_labels
      }
      spec {
        container {
          name  = var.app_name
          image = var.app_image_path
          port {
            container_port = 3000
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config.metadata.name
            }
          }
          env {
            name  = "DB_USER"
            value = var.db_user
          }
          env {
            name  = "DB_DATABASE"
            value = var.db_name
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = var.db_password_secret_name
                key  = "DB_PASSWORD"
              }
            }
          }
          liveness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
          readiness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
  depends_on = [
    kubernetes_config_map.app_config,
    # We will create the secret in the root module and pass its name in
  ]
}

// --- Application Service (ClusterIP) ---
// This service exposes the app inside the cluster. The Ingress will target it.
resource "kubernetes_service" "app" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = var.app_namespace
    labels    = var.app_labels
  }
  spec {
    type = "ClusterIP" // Exposes the service on a cluster-internal IP.
    selector = var.app_labels
    port {
      port        = 80
      target_port = 3000
      protocol    = "TCP"
      name        = "http"
    }
  }
}

// --- Ingress for ALB ---
// This resource tells GKE how to configure the ALB to route traffic to my service.
resource "kubernetes_ingress_v1" "app_ingress" {
  metadata {
    name      = "${var.app_name}-ingress"
    namespace = var.app_namespace
    labels    = var.app_labels
    annotations = {
      // This annotation specifies the name of the existing ALB backend service to use.
      // So /I will construct this name in the root module and pass it in.
      "kubernetes.io/ingress.backend-service" = "${var.app_name}-backend-service"
    }
  }
  spec {
    default_backend {
      service {
        name = kubernetes_service.app.metadata.name
        port {
          number = 80
        }
      }
    }
  }
}


// --- Database Schema Initialization Job ---
resource "kubernetes_config_map" "db_schema" {
  metadata {
    name      = "${var.app_name}-db-schema"
    namespace = var.app_namespace
    labels    = var.app_labels
  }
  data = {
    "queries.sql" = var.db_schema_sql
  }
}

resource "kubernetes_job" "db_init_job" {
  metadata {
    name      = "${var.app_name}-db-init-job"
    namespace = var.app_namespace
    labels    = var.app_labels
  }
  spec {
    template {
      metadata {
        name = "${var.app_name}-db-init-pod"
      }
      spec {
        container {
          name  = "db-init-container"
          image = "postgres:14-alpine"
          command = [
            "/bin/sh",
            "-c",
            "psql -f /sql/queries.sql"
          ]
          env {
            name  = "PGHOST"
            value = var.db_host
          }
          env {
            name  = "PGPORT"
            value = var.db_port
          }
          env {
            name  = "PGUSER"
            value = var.db_user
          }
          env {
            name  = "PGDATABASE"
            value = var.db_name
          }
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = var.db_password_secret_name
                key  = "DB_PASSWORD"
              }
            }
          }
          volume_mount {
            name       = "sql-script-volume"
            mount_path = "/sql"
          }
        }
        volume {
          name = "sql-script-volume"
          config_map {
            name = kubernetes_config_map.db_schema.metadata.name
          }
        }
        restart_policy = "Never"
      }
    }
    backoff_limit = 4
  }
}