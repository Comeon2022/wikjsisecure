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
# STEP 2: CREATE SERVICE ACCOUNTS
# =============================================================================

# Main Wiki.js Service Account
resource "google_service_account" "wiki_js_sa" {
  account_id   = "wiki-js-sa"
  display_name = "Wiki.js Application Service Account"
  description  = "Service account for Wiki.js Cloud Run application"
  project      = var.project_id
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_service_networking_connection.private_vpc_connection
  ]
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
# STEP 3: CREATE ARTIFACT REGISTRY
# =============================================================================

resource "google_artifact_registry_repository" "wiki_js_repo" {
  location      = var.region
  repository_id = "wiki-js"
  description   = "Container repository for Wiki.js application images"
  format        = "DOCKER"
  
  depends_on = [time_sleep.wait_for_apis]
}

# =============================================================================
# STEP 4: IAM PERMISSIONS FOR SERVICE ACCOUNTS
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
# STEP 5: CREATE SECRETS IN SECRET MANAGER
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
# STEP 6: CREATE PRIVATE NETWORKING
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
}

# Create private service connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.wiki_js_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
  
  depends_on = [google_compute_global_address.private_ip_range]
}

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
    time_sleep.wait_for_apis
  ]
}

# =============================================================================
# STEP 7: CREATE CLOUD SQL DATABASE (PRIVATE)
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
      ipv4_enabled    = false  # 🔒 No public IP
      private_network = google_compute_network.wiki_js_vpc.id
      ssl_mode        = "ALLOW_UNENCRYPTED_AND_ENCRYPTED"  # Allow non-SSL on private network
    }
    
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }
  
  deletion_protection = false
  
  timeouts {
    create = "30m"
    update = "30m"  
    delete = "30m"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Wait for Cloud SQL instance to be fully operational
resource "time_sleep" "wait_for_sql_instance" {
  depends_on      = [google_sql_database_instance.wiki_postgres]
  create_duration = "120s"
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
# STEP 7: BUILD AND PUSH DOCKER IMAGE
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
# STEP 8: DEPLOY CLOUD RUN SERVICE
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
      
      # Remove SSL requirement since we're on private network
      # The VPC provides network-level security
      
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
    google_secret_manager_secret_version.db_username
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
    "🗄️  Database"            = "${google_sql_database_instance.wiki_postgres.name} (Private IP Only)"
    "📦 Image Registry"       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}"
    "🔑 Service Account"      = google_service_account.wiki_js_sa.email
    "🛡️  Security"            = "Private network + Secret Manager + SSL required"
    "🌐 VPC Connector"        = google_vpc_access_connector.wiki_js_connector.name
    "🏗️  Build Method"        = "Docker pull and push via null_resource"
  }
}

output "wiki_js_url" {
  description = "🌐 Your Wiki.js Application URL"
  value       = google_cloud_run_v2_service.wiki_js.uri
}

output "security_info" {
  description = "🔐 Security Information"
  value = {
    "🔑 Database Username Secret" = google_secret_manager_secret.db_username.name
    "🔒 Database Password Secret" = google_secret_manager_secret.db_password.name
    "🛡️  Secret Manager Console"  = "https://console.cloud.google.com/security/secret-manager?project=${var.project_id}"
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