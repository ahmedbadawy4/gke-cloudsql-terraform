locals {
  # Cloud SQL for PostgreSQL accepts only a fixed list of flags. pgaudit and
  # the audit_log flag are not in it, so statement logging is limited to these.
  sql_database_flags = {
    log_duration                = "on"
    log_statement               = "ddl"
    log_min_messages            = "error"
    log_connections             = "on"
    log_disconnections          = "on"
    log_lock_waits              = "on"
    log_temp_files              = "0"
    log_autovacuum_min_duration = "0"
    log_checkpoints             = "on"
    log_line_prefix             = "%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "
    log_timezone                = "UTC"
  }
}

resource "google_sql_database_instance" "main" {
  name                = "${local.name}-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = var.deletion_protection

  settings {
    tier                        = var.sql_tier
    edition                     = "ENTERPRISE"
    availability_type           = var.sql_availability_type
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    dynamic "database_flags" {
      for_each = local.sql_database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
      ssl_mode        = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "app" {
  name     = var.database_name
  instance = google_sql_database_instance.main.name
}
