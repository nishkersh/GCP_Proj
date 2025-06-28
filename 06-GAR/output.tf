output "repository_id" {
  description = "The ID of the Artifact Registry repository."
  value       = google_artifact_registry_repository.default.repository_id
}

output "repository_name" {
  description = "The full name of the Artifact Registry repository (projects/PROJECT_ID/locations/REGION/repositories/REPOSITORY_ID)."
  value       = google_artifact_registry_repository.default.name
  sensitive   = true
}

output "repository_url" {
  description = "The full URL prefix for Docker images in this repository (e.g., REGION-docker.pkg.dev/PROJECT_ID/REPOSITORY_ID)."
  value       = "${google_artifact_registry_repository.default.location}-docker.pkg.dev/${google_artifact_registry_repository.default.project}/${google_artifact_registry_repository.default.repository_id}"
  sensitive   = true
}

output "format" {
  description = "The format of the repository."
  value       = google_artifact_registry_repository.default.format
}

output "location" {
  description = "The region where the repository is located."
  value       = google_artifact_registry_repository.default.location
}

output "kms_key_name" {
  description = "The KMS key used for encrypting artifacts, if configured."
  value       = google_artifact_registry_repository.default.kms_key_name
}