variable "app_name" {
  description = "The name of the application."
  type        = string
  default     = "two-tier-app"
}
variable "app_namespace" {
  description = "The Kubernetes namespace to deploy the application into."
  type        = string
}
variable "app_image_path" {
  description = "The full path to the application's Docker image in Artifact Registry."
  type        = string
}
variable "app_replicas" {
  description = "The number of pod replicas for the application deployment."
  type        = number
  default     = 2
}
variable "db_host" {
  description = "The hostname or IP address of the Cloud SQL database."
  type        = string
}
variable "db_port" {
  description = "The port for the Cloud SQL database."
  type        = string
  default     = "5432"
}
variable "db_user" {
  description = "The database username."
  type        = string
}
variable "db_name" {
  description = "The name of the database."
  type        = string
}
variable "db_password_secret_name" {
  description = "The name of the Kubernetes secret holding the database password."
  type        = string
}
variable "db_schema_sql" {
  description = "The content of the SQL schema initialization script."
  type        = string
}
variable "app_labels" {
  description = "A map of labels to apply to all application resources."
  type        = map(string)
  default     = {}
}