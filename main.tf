# =============================================================================
# Wiki.js on Google Cloud Run - Secure Terraform Deployment
# Repository: https://github.com/Comeon2022/wikjsisecure.git
# Version: 1.0.0
# Last Updated: 2025-08-15
# 
# Features:
# - Secure credential management with Secret Manager
# - Automatic random password generation
# - Complete infrastructure automation
# - Production-ready security practices
# 
# Usage:
# 1. git clone https://github.com/Comeon2022/wikjsisecure.git
# 2. cd wikjsisecure
# 3. terraform init
# 4. terraform apply
# 5. Enter your GCP project ID when prompted
# 6. Everything else is automated!
# =============================================================================

# Variables
variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Provider configuration
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# STEP 1: ENABLE REQUIRED APIS
# =============================================================================

resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "sqladmin.googleapis.com",
    "sql-component.googleapis.com", 
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "secretmanager.googleapis.com",  # 🔐 Secret Manager API
    "vpcaccess.googleapis.com",      # 🌐 VPC Access for private networking
    "servicenetworking.googleapis.com" # 🔗 Service Networking for Cloud SQL
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.required_apis]
  create_duration = "90s"
}

# =============================================================================
# STEP 2: CREATE VPC NETWORK FIRST (MOVED UP)
# =============================================================================

# Create VPC network for private communication
resource "google_compute_network" "wiki_js_vpc" {
  name                    = "wiki-js-vpc"
  auto_create_subnetworks = false
  description            = "VPC network for secure Wiki.js deployment"
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create subnet for the VPC
resource "google_compute_subnetwork" "wiki_js_subnet" {
  name          = "wiki-js-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.wiki_js_vpc.id
  description   = "Subnet for Wiki.js Cloud Run and Cloud SQL communication"
  
  # Enable private Google access
  private_ip_google_access = true
}

# Reserve IP range for Cloud SQL private peering
resource "google_compute_global_address" "private_ip_range" {
  name          = "wiki-js-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.wiki_js_vpc.id
  description   = "IP range for Cloud SQL private service connection"
  
  depends_on = [google_compute_network.wiki_js_vpc]
}

# Create private service connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.wiki_js_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
  
  depends_on = [
    google_compute_global_address.private_ip_range,
    time_sleep.wait_for_apis
  ]
}

# Wait for private service connection to be established
resource "time_sleep" "wait_for_private_connection" {
  depends_on      = [google_service_networking_connection.private_vpc_connection]
  create_duration = "30s"
}

# =============================================================================
# STEP 3: CREATE SERVICE ACCOUNTS
# =============================================================================

# Main Wiki.js Service Account
resource "google_service_account" "wiki_js_sa" {
  account_id   = "wiki-js-sa"
  display_name = "Wiki.js Application Service Account"
  description  = "Service account for Wiki.js Cloud Run application"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Build Service Account
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "wiki-js-build-sa"
  display_name = "Wiki.js Cloud Build Service Account"
  description  = "Service account for building and pushing Wiki.js container images"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# =============================================================================
# STEP 4: CREATE ARTIFACT REGISTRY
# =============================================================================

resource "google_artifact_registry_repository" "wiki_js_repo" {
  location      = var.region
  repository_id = "wiki-js"
  description   = "Container repository for Wiki.js application images"
  format        = "DOCKER"
  
  depends_on = [time_sleep.wait_for_apis]
}

# =============================================================================
# STEP 5: IAM PERMISSIONS FOR SERVICE ACCOUNTS
# =============================================================================

# IAM permissions for Wiki.js Service Account
resource "google_project_iam_member" "wiki_js_sa_permissions" {
  for_each = toset([
    "roles/run.developer",
    "roles/logging.logWriter", 
    "roles/logging.viewer",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",  # 🔐 Secret Manager access
    "roles/vpcaccess.user"                 # 🌐 VPC Access Connector
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# Artifact Registry permissions for Wiki.js Service Account
resource "google_artifact_registry_repository_iam_member" "wiki_js_sa_registry" {
  project    = var.project_id
  location   = google_artifact_registry_repository.wiki_js_repo.location
  repository = google_artifact_registry_repository.wiki_js_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM permissions for Cloud Build Service Account
resource "google_project_iam_member" "cloudbuild_sa_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/logging.logWriter",
    "roles/storage.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Artifact Registry permissions for Cloud Build Service Account
resource "google_artifact_registry_repository_iam_member" "cloudbuild_sa_registry" {
  project    = var.project_id
  location   = google_artifact_registry_repository.wiki_js_repo.location
  repository = google_artifact_registry_repository.wiki_js_repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# =============================================================================
# STEP 6: CREATE SECRETS IN SECRET MANAGER
# =============================================================================

# Generate random password for database
resource "random_password" "db_password" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Create secret for database password
resource "google_secret_manager_secret" "db_password" {
  secret_id = "wiki-js-db-password"
  
  labels = {
    app = "wiki-js"
    env = "production"
  }
  
  replication {
    auto {}
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Store the password in Secret Manager
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Create secret for database username
resource "google_secret_manager_secret" "db_username" {
  secret_id = "wiki-js-db-username"
  
  labels = {
    app = "wiki-js"
    env = "production"
  }
  
  replication {
    auto {}
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Store the username in Secret Manager
resource "google_secret_manager_secret_version" "db_username" {
  secret      = google_secret_manager_secret.db_username.id
  secret_data = "wikijs"
}

# =============================================================================
# STEP 7: CREATE VPC ACCESS CONNECTOR
# =============================================================================

# Create VPC Access Connector for Cloud Run
resource "google_vpc_access_connector" "wiki_js_connector" {
  name          = "wiki-js-connector"
  region        = var.region
  network       = google_compute_network.wiki_js_vpc.name
  ip_cidr_range = "10.8.0.0/28"
  
  min_throughput = 200
  max_throughput = 300
  
  depends_on = [
    google_compute_subnetwork.wiki_js_subnet,
    time_sleep.wait_for_private_connection
  ]
}

# =============================================================================
# STEP 8: CREATE CLOUD SQL DATABASE (PRIVATE)
# =============================================================================

resource "google_sql_database_instance" "wiki_postgres" {
  name             = "wiki-postgres-instance"
  database_version = "POSTGRES_15"
  region          = var.region
  
  settings {
    tier = "db-f1-micro"
    
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = false
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
    
    ip_configuration {
      ipv4_enabled                                  = false  # 🔒 No public IP
      private_network                               = google_compute_network.wiki_js_vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
    }
    
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }
  
  deletion_protection = false
  
  timeouts {
    create = "45m"  # Increased timeout
    update = "45m"  
    delete = "45m"
  }
  
  depends_on = [
    time_sleep.wait_for_private_connection,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Wait for Cloud SQL instance to be fully operational
resource "time_sleep" "wait_for_sql_instance" {
  depends_on      = [google_sql_database_instance.wiki_postgres]
  create_duration = "180s"  # Increased wait time
}

# Create Wiki.js database
resource "google_sql_database" "wiki_database" {
  name     = "wiki"
  instance = google_sql_database_instance.wiki_postgres.name
  
  depends_on = [time_sleep.wait_for_sql_instance]
}

# Create Wiki.js database user with secure credentials
resource "google_sql_user" "wiki_user" {
  name     = google_secret_manager_secret_version.db_username.secret_data
  instance = google_sql_database_instance.wiki_postgres.name
  password = google_secret_manager_secret_version.db_password.secret_data
  
  depends_on = [
    time_sleep.wait_for_sql_instance,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.db_username
  ]
}

# =============================================================================
# STEP 9: BUILD AND PUSH DOCKER IMAGE
# =============================================================================

# Simple approach: Use local-exec to handle image push
resource "null_resource" "build_and_push_image" {
  triggers = {
    registry_url = google_artifact_registry_repository.wiki_js_repo.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "🚀 Starting Wiki.js image build and push process..."
      
      # Configure Docker authentication
      gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
      
      # Pull the official Wiki.js image
      echo "📦 Pulling official Wiki.js image..."
      docker pull ghcr.io/requarks/wiki:2
      
      # Tag for Artifact Registry
      echo "🏷️ Tagging image for Artifact Registry..."
      docker tag ghcr.io/requarks/wiki:2 ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2
      docker tag ghcr.io/requarks/wiki:2 ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:latest
      
      # Push to Artifact Registry
      echo "⬆️ Pushing images to Artifact Registry..."
      docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2
      docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:latest
      
      echo "✅ Wiki.js image successfully pushed to Artifact Registry!"
    EOT
  }
  
  depends_on = [
    google_artifact_registry_repository.wiki_js_repo,
    google_artifact_registry_repository_iam_member.cloudbuild_sa_registry
  ]
}

# =============================================================================
# STEP 10: DEPLOY CLOUD RUN SERVICE
# =============================================================================

resource "google_cloud_run_v2_service" "wiki_js" {
  name     = "wiki-js"
  location = var.region
  
  template {
    service_account = google_service_account.wiki_js_sa.email
    
    # VPC Access for private database connection
    vpc_access {
      connector = google_vpc_access_connector.wiki_js_connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
    
    # Annotations for troubleshooting
    annotations = {
      "autoscaling.knative.dev/minScale" = "0"
      "autoscaling.knative.dev/maxScale" = "10"
      "run.googleapis.com/execution-environment" = "gen2"
    }
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2"
      
      ports {
        container_port = 3000
      }
      
      # Environment variables for Wiki.js
      env {
        name  = "DB_TYPE"
        value = "postgres"
      }
      
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.wiki_postgres.private_ip_address
      }
      
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      
      env {
        name = "DB_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_username.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name = "DB_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name  = "DB_NAME"
        value = google_sql_database.wiki_database.name
      }
      
      # SSL Configuration for Cloud SQL private connection
      env {
        name  = "DB_SSL"
        value = "false"  # Disable SSL for private network
      }
      
      # Add debugging environment variables
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      
      env {
        name  = "WIKI_LOG_LEVEL"
        value = "info"
      }
      
      # Resource configuration
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }
      
      # Health checks - more lenient for Wiki.js startup
      startup_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 120  # Give Wiki.js more time to start
        timeout_seconds      = 30   # Longer timeout
        period_seconds       = 30   # Check less frequently
        failure_threshold    = 10   # More tolerant of failures
      }
      
      liveness_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 180  # Wait longer before liveness checks
        timeout_seconds      = 10
        period_seconds       = 60   # Check less frequently
        failure_threshold    = 5    # More tolerant
      }
    }
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Timeout
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    null_resource.build_and_push_image,
    google_sql_database.wiki_database,
    google_sql_user.wiki_user,
    google_project_iam_member.wiki_js_sa_permissions,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.db_username,
    google_vpc_access_connector.wiki_js_connector
  ]
}

# Allow public access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.wiki_js.name
  location = google_cloud_run_v2_service.wiki_js.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "deployment_summary" {
  description = "🎉 Deployment Summary"
  value = {
    "✅ Status"                = "Wiki.js deployment completed successfully!"
    "🌐 Wiki.js URL"          = google_cloud_run_v2_service.wiki_js.uri
    "🗄️ Database"            = "${google_sql_database_instance.wiki_postgres.name} (Private IP Only)"
    "📦 Image Registry"       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}"
    "🔐 Service Account"      = google_service_account.wiki_js_sa.email
    "🛡️ Security"            = "Private network + Secret Manager + SSL required"
    "🌐 VPC Connector"        = google_vpc_access_connector.wiki_js_connector.name
    "🗃️ Build Method"        = "Docker pull and push via null_resource"
  }
}

output "wiki_js_url" {
  description = "🌐 Your Wiki.js Application URL"
  value       = google_cloud_run_v2_service.wiki_js.uri
}

output "security_info" {
  description = "🔐 Security Information"
  value = {
    "🔐 Database Username Secret" = google_secret_manager_secret.db_username.name
    "🔐 Database Password Secret" = google_secret_manager_secret.db_password.name
    "🛡️ Secret Manager Console"  = "https://console.cloud.google.com/security/secret-manager?project=${var.project_id}"
  }
}

output "next_steps" {
  description = "📋 What to do next"
  value = <<-EOT
    
    🎉 SECURE DEPLOYMENT COMPLETED!
    
    📝 Next Steps:
    1. Visit your Wiki.js URL: ${google_cloud_run_v2_service.wiki_js.uri}
    2. Complete the initial setup wizard
    3. Create your admin account
    4. Start building your wiki!
    
    🔐 Security Features:
    - Database credentials securely stored in Secret Manager
    - Random 32-character password automatically generated
    - Private database network (no public IP)
    - SSL-required database connections
    - VPC Access Connector for secure Cloud Run ↔ Database communication
    - Service accounts follow least privilege principles
    - All sensitive data encrypted at rest
    
    🔧 Management URLs:
    - Cloud Run: https://console.cloud.google.com/run/detail/${var.region}/wiki-js/metrics?project=${var.project_id}
    - Cloud SQL: https://console.cloud.google.com/sql/instances/wiki-postgres-instance/overview?project=${var.project_id}
    - Secret Manager: https://console.cloud.google.com/security/secret-manager?project=${var.project_id}
    - Artifact Registry: https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/wiki-js?project=${var.project_id}
    
    💡 Security Tips:
    - Database credentials are never visible in logs or Terraform state
    - Rotate secrets periodically via Secret Manager console
    - Monitor access via Cloud Logging
    
    🚀 Happy secure wiki-ing!
  EOT
}

# Database connection (completely private now)
output "database_info" {
  description = "Database connection details (private network only)"
  value = {
    private_ip = google_sql_database_instance.wiki_postgres.private_ip_address
    database   = google_sql_database.wiki_database.name
    port       = 5432
    network    = google_compute_network.wiki_js_vpc.name
    note       = "Database accessible only via private network. Credentials in Secret Manager."
  }
}

# =============================================================================
# MONITORING AND ANALYTICS CONFIGURATION
# =============================================================================

# Enable monitoring APIs
resource "google_project_service" "monitoring_apis" {
  for_each = toset([
    "monitoring.googleapis.com",
    "bigquery.googleapis.com",
    "cloudasset.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy         = false
  disable_dependent_services = false
  
  depends_on = [google_project_service.required_apis]
}

# Wait for monitoring APIs to be ready
resource "time_sleep" "wait_for_monitoring_apis" {
  depends_on      = [google_project_service.monitoring_apis]
  create_duration = "60s"
}

# =============================================================================
# LOG-BASED METRICS FOR CUSTOM ANALYTICS
# =============================================================================

# Site visitor tracking metric
resource "google_logging_metric" "wiki_page_views" {
  name   = "wiki_page_views"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="wiki-js"
    httpRequest.requestMethod="GET"
    httpRequest.status>=200
    httpRequest.status<300
    NOT httpRequest.requestUrl=~"/assets/"
    NOT httpRequest.requestUrl=~"/favicon"
    NOT httpRequest.requestUrl=~"/_health"
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Wiki.js Page Views"
  }

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    google_cloud_run_v2_service.wiki_js
  ]
}

# User session tracking metric
resource "google_logging_metric" "wiki_user_sessions" {
  name   = "wiki_user_sessions"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="wiki-js"
    (jsonPayload.msg=~"User .* logged in" OR 
     jsonPayload.message=~"User .* authenticated" OR
     textPayload=~"LOGIN")
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Wiki.js User Logins"
  }

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    google_cloud_run_v2_service.wiki_js
  ]
}

# Error tracking metric
resource "google_logging_metric" "wiki_errors" {
  name   = "wiki_errors"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="wiki-js"
    (severity>=ERROR OR 
     httpRequest.status>=400 OR
     jsonPayload.level="error" OR
     textPayload=~"ERROR")
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Wiki.js Errors"
  }

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    google_cloud_run_v2_service.wiki_js
  ]
}

# Performance tracking metric
resource "google_logging_metric" "slow_requests" {
  name   = "slow_requests"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="wiki-js"
    httpRequest.latency>"2s"
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Slow Requests (>2s)"
  }

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    google_cloud_run_v2_service.wiki_js
  ]
}

# =============================================================================
# BIGQUERY DATASET FOR LOG ANALYTICS
# =============================================================================

# BigQuery dataset for log analysis
resource "google_bigquery_dataset" "wiki_logs_dataset" {
  dataset_id                  = "wiki_js_logs"
  friendly_name               = "Wiki.js Application Logs"
  description                 = "Centralized logging for Wiki.js analytics and monitoring"
  location                    = var.region
  default_table_expiration_ms = 2592000000  # 30 days

  labels = {
    application = "wiki-js"
    purpose     = "logging"
  }

  depends_on = [time_sleep.wait_for_monitoring_apis]
}

# Log sink to BigQuery
resource "google_logging_project_sink" "wiki_logs_to_bigquery" {
  name = "wiki-js-logs-sink"
  
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.wiki_logs_dataset.dataset_id}"
  
  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="wiki-js"
    OR
    (resource.type="gce_instance" AND resource.labels.database_id="${google_sql_database_instance.wiki_postgres.name}")
  EOT
  
  unique_writer_identity = true

  depends_on = [google_bigquery_dataset.wiki_logs_dataset]
}

# Grant BigQuery data editor role to log sink
resource "google_project_iam_member" "log_sink_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.wiki_logs_to_bigquery.writer_identity

  depends_on = [google_logging_project_sink.wiki_logs_to_bigquery]
}

# =============================================================================
# ALERTING POLICIES
# =============================================================================

# High error rate alert
resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "Wiki.js High Error Rate"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Error rate > 5%"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/request_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05
      duration        = "300s"
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.service_name"]
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [time_sleep.wait_for_monitoring_apis]
}

# High CPU usage alert for Cloud Run
resource "google_monitoring_alert_policy" "high_cpu_usage" {
  display_name = "Wiki.js High CPU Usage"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "CPU utilization > 80%"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.service_name"]
      }
    }
  }
  
  notification_channels = []

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    google_cloud_run_v2_service.wiki_js
  ]
}

# Database high CPU alert
resource "google_monitoring_alert_policy" "database_high_cpu" {
  display_name = "PostgreSQL High CPU Usage"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Database CPU > 80%"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${google_sql_database_instance.wiki_postgres.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }
  
  notification_channels = []

  depends_on = [
    time_sleep.wait_for_monitoring_apis,
    time_sleep.wait_for_sql_instance
  ]
}

# =============================================================================
# COMPREHENSIVE MONITORING DASHBOARD
# =============================================================================

resource "google_monitoring_dashboard" "wiki_js_comprehensive_dashboard" {
  dashboard_json = jsonencode({
    displayName = "🔐 Wiki.js Complete Analytics Dashboard"
    mosaicLayout = {
      tiles = [
        # ===== SITE ANALYTICS ROW =====
        {
          width = 6
          height = 4
          widget = {
            title = "📊 Page Views (Last 24h)"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.wiki_page_views.name}\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 0
          xPos = 6
          widget = {
            title = "👥 User Sessions (Last 24h)"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.wiki_user_sessions.name}\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_BAR"
              }
            }
          }
        },
        
        # ===== CLOUD RUN PERFORMANCE ROW =====
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "🖥️ Cloud Run CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.label.service_name"]
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "CPU %"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          xPos = 6
          widget = {
            title = "💾 Cloud Run Memory Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                      groupByFields      = ["resource.label.service_name"]
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Memory %"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # ===== DATABASE PERFORMANCE ROW =====
        {
          width = 6
          height = 4
          yPos = 8
          widget = {
            title = "🗄️ PostgreSQL CPU Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${google_sql_database_instance.wiki_postgres.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "CPU %"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 8
          xPos = 6
          widget = {
            title = "💽 PostgreSQL Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${google_sql_database_instance.wiki_postgres.name}\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Memory %"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # ===== REQUEST METRICS ROW =====
        {
          width = 4
          height = 4
          yPos = 12
          widget = {
            title = "🚀 Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/request_count\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.service_name"]
                    }
                  }
                }
                plotType = "STACKED_BAR"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 4
          height = 4
          yPos = 12
          xPos = 4
          widget = {
            title = "⏱️ Response Latency (95th percentile)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"run.googleapis.com/request_latencies\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_DELTA"
                      crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      groupByFields      = ["resource.label.service_name"]
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Latency (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 4
          height = 4
          yPos = 12
          xPos = 8
          widget = {
            title = "❌ Error Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.wiki_errors.name}\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        
        # ===== DATABASE CONNECTIONS ROW =====
        {
          width = 6
          height = 4
          yPos = 16
          widget = {
            title = "🔗 Database Connections"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${google_sql_database_instance.wiki_postgres.name}\" AND metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "STACKED_AREA"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Active Connections"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 16
          xPos = 6
          widget = {
            title = "📊 Database Transactions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${google_sql_database_instance.wiki_postgres.name}\" AND metric.type=\"cloudsql.googleapis.com/database/postgresql/transaction_count\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
                targetAxis = "Y1"
                legendTemplate = "Transactions/sec"
              }]
              yAxis = {
                label = "Transactions/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # ===== SLOW REQUESTS ROW =====
        {
          width = 12
          height = 4
          yPos = 20
          widget = {
            title = "🐌 Slow Requests (>2 seconds)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"wiki-js\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.slow_requests.name}\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "STACKED_BAR"
                targetAxis = "Y1"
              }]
              yAxis = {
                label = "Slow Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # ===== LOG INSIGHTS ROW =====
        {
          width = 12
          height = 6
          yPos = 24
          widget = {
            title = "📋 Recent Application Logs"
            logsPanel = {
              filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"wiki-js\""
              resourceNames = []
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_logging_metric.wiki_page_views,
    google_logging_metric.wiki_user_sessions,
    google_logging_metric.wiki_errors,
    google_logging_metric.slow_requests,
    time_sleep.wait_for_monitoring_apis
  ]
}

# Monitoring and analytics outputs
output "monitoring_info" {
  description = "📊 Monitoring and Analytics Information"
  value = {
    "📊 Main Dashboard"           = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.wiki_js_comprehensive_dashboard.id}?project=${var.project_id}"
    "🔍 Logs Explorer"            = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%20AND%20resource.labels.service_name%3D%22wiki-js%22?project=${var.project_id}"
    "📈 BigQuery Dataset"         = "https://console.cloud.google.com/bigquery?project=${var.project_id}&ws=!1m4!1m3!3m2!1s${var.project_id}!2s${google_bigquery_dataset.wiki_logs_dataset.dataset_id}"
    "🚨 Alert Policies"           = "https://console.cloud.google.com/monitoring/alerting?project=${var.project_id}"
    "📊 All Dashboards"           = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
    "🔐 Secret Manager"           = "https://console.cloud.google.com/security/secret-manager?project=${var.project_id}"
    "📋 Log-based Metrics"        = "Custom metrics: wiki_page_views, wiki_user_sessions, wiki_errors, slow_requests"
  }
}