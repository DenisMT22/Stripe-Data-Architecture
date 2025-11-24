# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - GCP INFRASTRUCTURE
# ═══════════════════════════════════════════════════════════════════
# Cloud : Google Cloud Platform
# Stratégie : Deploy → Capture → Destroy (économie coûts)
# ═══════════════════════════════════════════════════════════════════

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# ───────────────────────────────────────────────────────────────────
# PROVIDER CONFIGURATION
# ───────────────────────────────────────────────────────────────────

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ───────────────────────────────────────────────────────────────────
# ACTIVATION DES APIs NÉCESSAIRES
# ───────────────────────────────────────────────────────────────────

resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "bigquery.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "composer.googleapis.com",
    "dataflow.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 1 : OLTP - CLOUD SQL (PostgreSQL)
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure SQL Database
# Tier gratuit éligible : db-f1-micro
# ───────────────────────────────────────────────────────────────────

resource "google_sql_database_instance" "stripe_oltp" {
  name             = "${var.project_name}-oltp-${var.environment}"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier              = var.sql_tier
    availability_type = "ZONAL" # Pas de HA pour économiser
    disk_size         = 10      # 10 GB minimum
    disk_type         = "PD_SSD"

    backup_configuration {
      enabled            = true
      start_time         = "03:00"
      point_in_time_recovery_enabled = false # Économie
      backup_retention_settings {
        retained_backups = 7
      }
    }

    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "allow-all-temp"
        value = "0.0.0.0/0" # ⚠️ À restreindre en production
      }
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    insights_config {
      query_insights_enabled = true
      query_string_length    = 1024
    }
  }

  deletion_protection = false # Permet destroy rapide

  depends_on = [google_project_service.required_apis]
}

resource "google_sql_database" "stripe_oltp_db" {
  name     = var.oltp_database_name
  instance = google_sql_database_instance.stripe_oltp.name
}

resource "google_sql_user" "stripe_admin" {
  name     = var.sql_admin_username
  instance = google_sql_database_instance.stripe_oltp.name
  password = var.sql_admin_password
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 2 : OLAP - BIGQUERY
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure Synapse Analytics
# Partitionnement par jour + Clustering pour performance
# ───────────────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "stripe_olap" {
  dataset_id    = var.bigquery_dataset_id
  friendly_name = "Stripe OLAP Star Schema"
  description   = "Data Warehouse pour analyses Stripe (RNCP 7)"
  location      = "EU"

  default_table_expiration_ms = null # Pas d'expiration

  labels = {
    environment = var.environment
    project     = var.project_name
    cost_center = "data-analytics"
  }

  depends_on = [google_project_service.required_apis]
}

# Table de fait principale avec partitionnement
resource "google_bigquery_table" "fact_transactions" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  table_id   = "fact_transactions"

  time_partitioning {
    type  = "DAY"
    field = "transaction_datetime"
  }

  clustering = ["customer_key", "merchant_key", "payment_method_key"]

  schema = jsonencode([
    {
      name = "transaction_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "transaction_datetime"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "time_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "customer_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "merchant_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "payment_method_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "geography_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "product_key"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "amount"
      type = "NUMERIC"
      mode = "REQUIRED"
    },
    {
      name = "currency"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "is_fraud"
      type = "BOOLEAN"
      mode = "REQUIRED"
    },
    {
      name = "processing_time_ms"
      type = "INT64"
      mode = "NULLABLE"
    }
  ])

  deletion_protection = false
}

# Dimensions
resource "google_bigquery_table" "dim_customer" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  table_id   = "dim_customer"

  schema = jsonencode([
    { name = "customer_key", type = "INT64", mode = "REQUIRED" },
    { name = "customer_id", type = "STRING", mode = "REQUIRED" },
    { name = "email", type = "STRING", mode = "REQUIRED" },
    { name = "full_name", type = "STRING", mode = "REQUIRED" },
    { name = "country", type = "STRING", mode = "REQUIRED" },
    { name = "customer_type", type = "STRING", mode = "REQUIRED" },
    { name = "valid_from", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_current", type = "BOOLEAN", mode = "REQUIRED" }
  ])

  deletion_protection = false
}

resource "google_bigquery_table" "dim_merchant" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  table_id   = "dim_merchant"

  schema = jsonencode([
    { name = "merchant_key", type = "INT64", mode = "REQUIRED" },
    { name = "merchant_id", type = "STRING", mode = "REQUIRED" },
    { name = "business_name", type = "STRING", mode = "REQUIRED" },
    { name = "industry", type = "STRING", mode = "REQUIRED" },
    { name = "country", type = "STRING", mode = "REQUIRED" },
    { name = "valid_from", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "valid_to", type = "TIMESTAMP", mode = "NULLABLE" },
    { name = "is_current", type = "BOOLEAN", mode = "REQUIRED" }
  ])

  deletion_protection = false
}

resource "google_bigquery_table" "dim_time" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  table_id   = "dim_time"

  schema = jsonencode([
    { name = "time_key", type = "INT64", mode = "REQUIRED" },
    { name = "full_date", type = "DATE", mode = "REQUIRED" },
    { name = "year", type = "INT64", mode = "REQUIRED" },
    { name = "quarter", type = "INT64", mode = "REQUIRED" },
    { name = "month", type = "INT64", mode = "REQUIRED" },
    { name = "day", type = "INT64", mode = "REQUIRED" },
    { name = "day_of_week", type = "INT64", mode = "REQUIRED" },
    { name = "is_weekend", type = "BOOLEAN", mode = "REQUIRED" }
  ])

  deletion_protection = false
}

# Table agrégée pour dashboards
resource "google_bigquery_table" "agg_daily_revenue" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  table_id   = "agg_daily_revenue"

  time_partitioning {
    type  = "DAY"
    field = "transaction_date"
  }

  schema = jsonencode([
    { name = "transaction_date", type = "DATE", mode = "REQUIRED" },
    { name = "merchant_key", type = "INT64", mode = "REQUIRED" },
    { name = "total_transactions", type = "INT64", mode = "REQUIRED" },
    { name = "total_revenue", type = "NUMERIC", mode = "REQUIRED" },
    { name = "avg_transaction_value", type = "NUMERIC", mode = "REQUIRED" },
    { name = "fraud_count", type = "INT64", mode = "REQUIRED" }
  ])

  deletion_protection = false
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 3 : NoSQL - FIRESTORE
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure Cosmos DB
# Mode Native pour scalabilité
# ───────────────────────────────────────────────────────────────────

resource "google_firestore_database" "stripe_nosql" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.required_apis]
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 4 : STORAGE - CLOUD STORAGE
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure Blob Storage
# Data Lake pour fichiers CSV, logs, backups
# ───────────────────────────────────────────────────────────────────

resource "google_storage_bucket" "datalake" {
  name          = "${var.project_id}-${var.project_name}-datalake"
  location      = "EU"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 90 # Supprimer après 90 jours
    }
  }

  labels = {
    environment = var.environment
    project     = var.project_name
  }

  force_destroy = true # Permet destroy même si contenu
}

# Dossiers logiques dans le bucket
resource "google_storage_bucket_object" "folders" {
  for_each = toset([
    "raw/",
    "processed/",
    "backups/",
    "logs/",
    "exports/"
  ])

  bucket  = google_storage_bucket.datalake.name
  name    = each.key
  content = " "
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 5 : STREAMING - PUB/SUB
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure Event Hubs
# Ingestion temps réel des transactions
# ───────────────────────────────────────────────────────────────────

resource "google_pubsub_topic" "stripe_transactions" {
  name = "${var.project_name}-transactions"

  message_retention_duration = "604800s" # 7 jours

  labels = {
    environment = var.environment
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "transactions_pull" {
  name  = "${var.project_name}-transactions-pull"
  topic = google_pubsub_topic.stripe_transactions.name

  message_retention_duration = "604800s" # 7 jours
  retain_acked_messages      = false

  ack_deadline_seconds = 20

  expiration_policy {
    ttl = "" # Jamais expirer
  }
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 6 : SECRET MANAGER
# ═══════════════════════════════════════════════════════════════════
# Équivalent Azure Key Vault
# Gestion sécurisée des credentials
# ───────────────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "sql_password" {
  secret_id = "${var.project_name}-sql-admin-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "sql_password_version" {
  secret      = google_secret_manager_secret.sql_password.id
  secret_data = var.sql_admin_password
}

# ═══════════════════════════════════════════════════════════════════
# COMPOSANT 7 : IAM - SERVICE ACCOUNTS
# ═══════════════════════════════════════════════════════════════════
# Comptes de service pour ETL/Pipelines
# ───────────────────────────────────────────────────────────────────

resource "google_service_account" "etl_pipeline" {
  account_id   = "${var.project_name}-etl-sa"
  display_name = "Stripe ETL Pipeline Service Account"
  description  = "Service account pour pipelines ETL OLTP → OLAP"
}

# Permissions BigQuery
resource "google_bigquery_dataset_iam_member" "etl_bigquery_admin" {
  dataset_id = google_bigquery_dataset.stripe_olap.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.etl_pipeline.email}"
}

# Permissions Cloud SQL
resource "google_project_iam_member" "etl_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.etl_pipeline.email}"
}

# Permissions Cloud Storage
resource "google_storage_bucket_iam_member" "etl_storage_admin" {
  bucket = google_storage_bucket.datalake.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.etl_pipeline.email}"
}

# Permissions Pub/Sub
resource "google_pubsub_topic_iam_member" "etl_pubsub_publisher" {
  topic  = google_pubsub_topic.stripe_transactions.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${google_service_account.etl_pipeline.email}"
}

# ═══════════════════════════════════════════════════════════════════
# MONITORING & ALERTING
# ═══════════════════════════════════════════════════════════════════

resource "google_monitoring_notification_channel" "email" {
  display_name = "Stripe Architecture Email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# ═══════════════════════════════════════════════════════════════════
# TAGGING & LABELS
# ═══════════════════════════════════════════════════════════════════

locals {
  common_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    certification = "rncp7-bloc2"
    cost_center = "data-platform"
  }
}