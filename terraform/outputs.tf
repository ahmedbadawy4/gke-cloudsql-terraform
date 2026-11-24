output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.main.name
}

output "cluster_location" {
  description = "Zone or region of the GKE cluster."
  value       = google_container_cluster.main.location
}

output "sql_private_ip" {
  description = "Private address of the Cloud SQL instance."
  value       = google_sql_database_instance.main.private_ip_address
}

output "sql_connection_name" {
  description = "Connection name for the Cloud SQL Auth Proxy."
  value       = google_sql_database_instance.main.connection_name
}

output "node_service_account" {
  description = "Service account that the cluster nodes run as."
  value       = google_service_account.gke_nodes.email
}

output "image_repository" {
  description = "Artifact Registry path that holds the application image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}
