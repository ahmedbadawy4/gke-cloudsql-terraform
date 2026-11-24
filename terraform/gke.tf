resource "google_container_cluster" "main" {
  name                     = "${local.name}-gke"
  location                 = local.cluster_location
  network                  = google_compute_network.main.id
  subnetwork               = google_compute_subnetwork.main.id
  deletion_protection      = var.deletion_protection
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range_name
    services_secondary_range_name = local.services_range_name
  }

  # Network policy enforcement needs both the add-on and the cluster setting.
  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_cidrs) > 0 ? [1] : []

    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_cidrs

        content {
          display_name = cidr_blocks.value.name
          cidr_block   = cidr_blocks.value.cidr
        }
      }
    }
  }
}

resource "google_container_node_pool" "main" {
  name               = "${local.name}-pool"
  location           = local.cluster_location
  cluster            = google_container_cluster.main.name
  initial_node_count = 1

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.node_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    tags            = [local.node_tag]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [
    google_project_iam_member.gke_nodes,
    google_artifact_registry_repository_iam_member.gke_nodes_reader,
  ]
}
