locals {
  name                = "${var.name_prefix}-${var.environment}"
  node_tag            = "${local.name}-node"
  pods_range_name     = "pods"
  services_range_name = "services"
  cluster_location    = var.regional_cluster ? var.region : "${var.region}-a"
}

resource "google_compute_network" "main" {
  name                    = "${local.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name                     = "${local.name}-subnet"
  region                   = var.region
  network                  = google_compute_network.main.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = local.services_range_name
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Address range that Google reserves for private services such as Cloud SQL.
# It is created after the subnet so that the allocator sees the subnet ranges.
resource "google_compute_global_address" "private_services" {
  name          = "${local.name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id

  depends_on = [google_compute_subnetwork.main]
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_compute_firewall" "allow_internal" {
  name          = "${local.name}-allow-internal"
  network       = google_compute_network.main.id
  source_ranges = [var.subnet_cidr, var.pods_cidr]

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }
}

# SSH to the nodes only through Identity-Aware Proxy.
resource "google_compute_firewall" "allow_iap_ssh" {
  name          = "${local.name}-allow-iap-ssh"
  network       = google_compute_network.main.id
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
