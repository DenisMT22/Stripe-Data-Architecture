# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - OUTPUTS GCP
# ═══════════════════════════════════════════════════════════════════
# Ces outputs affichent les informations de connexion après déploiement
# Utiliser : terraform output <nom_output>
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# INFORMATIONS GÉNÉRALES
# ───────────────────────────────────────────────────────────────────

output "project_id" {
  description = "ID du projet GCP"
  value       = var.project_id
}

output "region" {
  description = "Région de déploiement"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Date et heure du déploiement"
  value       = timestamp()
}

# ═══════════════════════════════════════════════════════════════════
# CLOUD SQL (OLTP)
# ═══════════════════════════════════════════════════════════════════

output "sql_instance_name" {
  description = "Nom de l'instance Cloud SQL"
  value       = google_sql_database_instance.stripe_oltp.name
}

output "sql_instance_connection_name" {
  description = "Connection name pour Cloud SQL Proxy"
  value       = google_sql_database_instance.stripe_oltp.connection_name
}

output "sql_public_ip" {
  description = "Adresse IP publique Cloud SQL"
  value       = google_sql_database_instance.stripe_oltp.public_ip_address
}

output "sql_database_name" {
  description = "Nom de la base de données OLTP"
  value       = google_sql_database.stripe_oltp_db.name
}

output "sql_connection_string" {
  description = "Chaîne de connexion PostgreSQL"
  value       = "postgresql://${var.sql_admin_username}@${google_sql_database_instance.stripe_oltp.public_ip_address}:5432/${google_sql_database.stripe_oltp_db.name}"
  sensitive   = false
}

output "sql_connection_command" {
  description = "Commande psql pour se connecter"
  value       = "psql -h ${google_sql_database_instance.stripe_oltp.public_ip_address} -U ${var.sql_admin_username} -d ${google_sql_database.stripe_oltp_db.name}"
}

# ═══════════════════════════════════════════════════════════════════
# BIGQUERY (OLAP)
# ═══════════════════════════════════════════════════════════════════

output "bigquery_dataset_id" {
  description = "ID du dataset BigQuery"
  value       = google_bigquery_dataset.stripe_olap.dataset_id
}

output "bigquery_dataset_location" {
  description = "Localisation du dataset BigQuery"
  value       = google_bigquery_dataset.stripe_olap.location
}

output "bigquery_console_url" {
  description = "URL console BigQuery"
  value       = "https://console.cloud.google.com/bigquery?project=${var.project_id}&p=${var.project_id}&d=${google_bigquery_dataset.stripe_olap.dataset_id}&page=dataset"
}

output "bigquery_tables" {
  description = "Liste des tables créées dans BigQuery"
  value = [
    google_bigquery_table.fact_transactions.table_id,
    google_bigquery_table.dim_customer.table_id,
    google_bigquery_table.dim_merchant.table_id,
    google_bigquery_table.dim_time.table_id,
    google_bigquery_table.agg_daily_revenue.table_id
  ]
}

output "bigquery_query_command" {
  description = "Commande bq pour exécuter requêtes"
  value       = "bq query --use_legacy_sql=false 'SELECT * FROM `${var.project_id}.${google_bigquery_dataset.stripe_olap.dataset_id}.fact_transactions` LIMIT 10'"
}

# ═══════════════════════════════════════════════════════════════════
# FIRESTORE (NoSQL)
# ═══════════════════════════════════════════════════════════════════

output "firestore_database_name" {
  description = "Nom de la base Firestore"
  value       = google_firestore_database.stripe_nosql.name
}

output "firestore_location" {
  description = "Localisation Firestore"
  value       = google_firestore_database.stripe_nosql.location_id
}

output "firestore_console_url" {
  description = "URL console Firestore"
  value       = "https://console.cloud.google.com/firestore/databases/-default-/data/panel?project=${var.project_id}"
}

# ═══════════════════════════════════════════════════════════════════
# CLOUD STORAGE
# ═══════════════════════════════════════════════════════════════════

output "storage_bucket_name" {
  description = "Nom du bucket Cloud Storage"
  value       = google_storage_bucket.datalake.name
}

output "storage_bucket_url" {
  description = "URL du bucket"
  value       = google_storage_bucket.datalake.url
}

output "storage_gsutil_command" {
  description = "Commande gsutil pour lister contenu"
  value       = "gsutil ls -r gs://${google_storage_bucket.datalake.name}/"
}

output "storage_console_url" {
  description = "URL console Cloud Storage"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.datalake.name}?project=${var.project_id}"
}

# ═══════════════════════════════════════════════════════════════════
# PUB/SUB
# ═══════════════════════════════════════════════════════════════════

output "pubsub_topic_name" {
  description = "Nom du topic Pub/Sub"
  value       = google_pubsub_topic.stripe_transactions.name
}

output "pubsub_subscription_name" {
  description = "Nom de la souscription Pub/Sub"
  value       = google_pubsub_subscription.transactions_pull.name
}

output "pubsub_console_url" {
  description = "URL console Pub/Sub"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/list?project=${var.project_id}"
}

output "pubsub_publish_command" {
  description = "Commande gcloud pour publier message"
  value       = "gcloud pubsub topics publish ${google_pubsub_topic.stripe_transactions.name} --message '{\"transaction_id\":\"test_001\",\"amount\":99.99}'"
}

# ═══════════════════════════════════════════════════════════════════
# SECRET MANAGER
# ═══════════════════════════════════════════════════════════════════

output "secret_sql_password_name" {
  description = "Nom du secret contenant le mot de passe SQL"
  value       = google_secret_manager_secret.sql_password.secret_id
}

output "secret_access_command" {
  description = "Commande pour récupérer le mot de passe SQL"
  value       = "gcloud secrets versions access latest --secret=${google_secret_manager_secret.sql_password.secret_id}"
  sensitive   = true
}

# ═══════════════════════════════════════════════════════════════════
# SERVICE ACCOUNTS
# ═══════════════════════════════════════════════════════════════════

output "etl_service_account_email" {
  description = "Email du service account ETL"
  value       = google_service_account.etl_pipeline.email
}

output "etl_service_account_key_command" {
  description = "Commande pour créer clé service account"
  value       = "gcloud iam service-accounts keys create key.json --iam-account=${google_service_account.etl_pipeline.email}"
}

# ═══════════════════════════════════════════════════════════════════
# URLS CONSOLE GCP
# ═══════════════════════════════════════════════════════════════════

output "gcp_console_urls" {
  description = "URLs des consoles GCP"
  value = {
    dashboard       = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    cloud_sql       = "https://console.cloud.google.com/sql/instances?project=${var.project_id}"
    bigquery        = "https://console.cloud.google.com/bigquery?project=${var.project_id}"
    firestore       = "https://console.cloud.google.com/firestore?project=${var.project_id}"
    cloud_storage   = "https://console.cloud.google.com/storage/browser?project=${var.project_id}"
    pubsub          = "https://console.cloud.google.com/cloudpubsub?project=${var.project_id}"
    secret_manager  = "https://console.cloud.google.com/security/secret-manager?project=${var.project_id}"
    iam             = "https://console.cloud.google.com/iam-admin/iam?project=${var.project_id}"
    billing         = "https://console.cloud.google.com/billing?project=${var.project_id}"
  }
}

# ═══════════════════════════════════════════════════════════════════
# COMMANDES UTILES
# ═══════════════════════════════════════════════════════════════════

output "useful_commands" {
  description = "Commandes gcloud utiles"
  value = {
    list_resources   = "gcloud projects describe ${var.project_id}"
    sql_connect      = "gcloud sql connect ${google_sql_database_instance.stripe_oltp.name} --user=${var.sql_admin_username}"
    bq_list_tables   = "bq ls ${var.project_id}:${google_bigquery_dataset.stripe_olap.dataset_id}"
    storage_list     = "gsutil ls gs://${google_storage_bucket.datalake.name}"
    check_apis       = "gcloud services list --enabled --project=${var.project_id}"
  }
}

# ═══════════════════════════════════════════════════════════════════
# COÛTS ESTIMÉS
# ═══════════════════════════════════════════════════════════════════

output "estimated_costs" {
  description = "Estimation des coûts mensuels (USD)"
  value = {
    cloud_sql_micro       = "~8 USD/mois (db-f1-micro avec 10GB)"
    bigquery_storage      = "~0.02 USD/GB/mois (prix stockage EU)"
    firestore             = "Gratuit jusqu'à 1GB + 50K lectures/jour"
    cloud_storage         = "~0.02 USD/GB/mois (STANDARD EU)"
    pubsub                = "Gratuit jusqu'à 10GB/mois"
    total_estimated       = "~10-15 USD/mois (usage minimal)"
    strategy              = "DEPLOY → CAPTURE → DESTROY (coût réel: ~0.50 USD/session)"
  }
}

# ═══════════════════════════════════════════════════════════════════
# INSTRUCTIONS POST-DÉPLOIEMENT
# ═══════════════════════════════════════════════════════════════════

output "next_steps" {
  description = "Prochaines étapes après déploiement"
  value = <<-EOT
    ╔════════════════════════════════════════════════════════════════╗
    ║  DÉPLOIEMENT RÉUSSI - PROCHAINES ÉTAPES                        ║
    ╚════════════════════════════════════════════════════════════════╝
    
    1️⃣  CONNEXION CLOUD SQL :
        psql -h ${google_sql_database_instance.stripe_oltp.public_ip_address} -U ${var.sql_admin_username} -d ${google_sql_database.stripe_oltp_db.name}
    
    2️⃣  REQUÊTES BIGQUERY :
        bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM `${var.project_id}.${google_bigquery_dataset.stripe_olap.dataset_id}.fact_transactions`'
    
    3️⃣  VÉRIFIER FIRESTORE :
        https://console.cloud.google.com/firestore?project=${var.project_id}
    
    4️⃣  CAPTURER SCREENS (10 captures nécessaires) :
        - Dashboard GCP
        - Cloud SQL instance
        - BigQuery dataset + tables
        - Firestore collections
        - Cloud Storage bucket
        - Pub/Sub topic
        - IAM permissions
        - Billing report
        - Terraform outputs
        - Architecture complète
    
    5️⃣  DÉTRUIRE RESSOURCES (après captures) :
        cd pipelines/terraform/gcp
        ./destroy.sh
    
    6️⃣  VÉRIFIER NETTOYAGE :
        ./verify_cleanup.sh
    
    ⚠️  IMPORTANT : Détruire les ressources dans les 3h pour économiser !
  EOT
}