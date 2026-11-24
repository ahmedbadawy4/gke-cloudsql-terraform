locals {
  node_roles = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/cloudsql.client",
  ])
}

# Identity of the cluster nodes. Without it the nodes would use the default
# Compute Engine service account, which has the broad Editor role.
resource "google_service_account" "gke_nodes" {
  account_id   = "${local.name}-gke-nodes"
  display_name = "${local.name} GKE nodes"
}

# Additive members, so roles that other teams grant to the same project stay.
resource "google_project_iam_member" "gke_nodes" {
  for_each = local.node_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_artifact_registry_repository_iam_member" "gke_nodes_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}
