# ═══════════════════════════════════════════════════════════════════
# STRIPE DATA ARCHITECTURE - VARIABLES GCP
# ═══════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────
# CONFIGURATION PROJET
# ───────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "ID du projet GCP (ex: stripe-data-architecture-123456)"
  type        = string
}

variable "project_name" {
  description = "Nom du projet (préfixe ressources)"
  type        = string
  default     = "stripe-data"
}

variable "environment" {
  description = "Environnement de déploiement"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "L'environnement doit être : dev, staging ou prod."
  }
}

# ───────────────────────────────────────────────────────────────────
# CONFIGURATION GÉOGRAPHIQUE
# ───────────────────────────────────────────────────────────────────

variable "region" {
  description = "Région GCP principale"
  type        = string
  default     = "europe-west1" # Belgique (proche France)

  validation {
    condition = contains([
      "europe-west1",  # Belgique
      "europe-west3",  # Allemagne
      "europe-west4",  # Pays-Bas
      "europe-west9"   # France (Paris)
    ], var.region)
    error_message = "La région doit être en Europe pour conformité RGPD."
  }
}

variable "zone" {
  description = "Zone GCP (pour ressources zonales)"
  type        = string
  default     = "europe-west1-b"
}

# ───────────────────────────────────────────────────────────────────
# CLOUD SQL (OLTP)
# ───────────────────────────────────────────────────────────────────

variable "sql_tier" {
  description = "Tier Cloud SQL (db-f1-micro pour free tier)"
  type        = string
  default     = "db-f1-micro"

  validation {
    condition = contains([
      "db-f1-micro",    # 0.6 GB RAM - FREE TIER éligible
      "db-g1-small",    # 1.7 GB RAM
      "db-n1-standard-1" # 3.75 GB RAM
    ], var.sql_tier)
    error_message = "Tier invalide. Utiliser db-f1-micro pour économiser."
  }
}

variable "oltp_database_name" {
  description = "Nom de la base de données OLTP"
  type        = string
  default     = "stripe_oltp"
}

variable "sql_admin_username" {
  description = "Nom d'utilisateur administrateur SQL"
  type        = string
  default     = "stripe_admin"
}

variable "sql_admin_password" {
  description = "Mot de passe administrateur SQL (sensible)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.sql_admin_password) >= 12
    error_message = "Le mot de passe doit contenir au moins 12 caractères."
  }
}

# ───────────────────────────────────────────────────────────────────
# BIGQUERY (OLAP)
# ───────────────────────────────────────────────────────────────────

variable "bigquery_dataset_id" {
  description = "ID du dataset BigQuery"
  type        = string
  default     = "stripe_olap"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.bigquery_dataset_id))
    error_message = "L'ID doit contenir uniquement lettres, chiffres et underscores."
  }
}

variable "bigquery_location" {
  description = "Localisation du dataset BigQuery"
  type        = string
  default     = "EU"

  validation {
    condition     = contains(["EU", "US"], var.bigquery_location)
    error_message = "La localisation doit être EU ou US."
  }
}

# ───────────────────────────────────────────────────────────────────
# FIRESTORE (NoSQL)
# ───────────────────────────────────────────────────────────────────

variable "firestore_location" {
  description = "Localisation Firestore"
  type        = string
  default     = "europe-west1"
}

# ───────────────────────────────────────────────────────────────────
# CLOUD STORAGE
# ───────────────────────────────────────────────────────────────────

variable "storage_class" {
  description = "Classe de stockage Cloud Storage"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD",
      "NEARLINE",  # Accès < 1 fois/mois
      "COLDLINE",  # Accès < 1 fois/trimestre
      "ARCHIVE"    # Accès < 1 fois/an
    ], var.storage_class)
    error_message = "Classe de stockage invalide."
  }
}

# ───────────────────────────────────────────────────────────────────
# PUB/SUB
# ───────────────────────────────────────────────────────────────────

variable "pubsub_message_retention_days" {
  description = "Durée de rétention messages Pub/Sub (jours)"
  type        = number
  default     = 7

  validation {
    condition     = var.pubsub_message_retention_days >= 1 && var.pubsub_message_retention_days <= 31
    error_message = "La rétention doit être entre 1 et 31 jours."
  }
}

# ───────────────────────────────────────────────────────────────────
# MONITORING
# ───────────────────────────────────────────────────────────────────

variable "alert_email" {
  description = "Email pour alertes monitoring"
  type        = string
  default     = "admin@stripe-data.local"
}

# ───────────────────────────────────────────────────────────────────
# TAGS & LABELS
# ───────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags communs à toutes les ressources"
  type        = map(string)
  default = {
    project       = "stripe-data-architecture"
    certification = "RNCP7-Bloc2"
    managed_by    = "terraform"
    cost_center   = "data-platform"
  }
}

# ───────────────────────────────────────────────────────────────────
# COÛTS & BUDGETS
# ───────────────────────────────────────────────────────────────────

variable "monthly_budget_usd" {
  description = "Budget mensuel en USD (alerte si dépassement)"
  type        = number
  default     = 50

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "Le budget doit être positif."
  }
}

# ───────────────────────────────────────────────────────────────────
# FEATURES FLAGS
# ───────────────────────────────────────────────────────────────────

variable "enable_high_availability" {
  description = "Activer haute disponibilité Cloud SQL (coûte 2x plus cher)"
  type        = bool
  default     = false
}

variable "enable_backups" {
  description = "Activer backups automatiques"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Activer monitoring et alertes"
  type        = bool
  default     = true
}

# ───────────────────────────────────────────────────────────────────
# PARAMÈTRES AVANCÉS
# ───────────────────────────────────────────────────────────────────

variable "sql_disk_size_gb" {
  description = "Taille disque Cloud SQL en GB"
  type        = number
  default     = 10

  validation {
    condition     = var.sql_disk_size_gb >= 10 && var.sql_disk_size_gb <= 10000
    error_message = "La taille doit être entre 10 GB et 10 TB."
  }
}

variable "sql_max_connections" {
  description = "Nombre maximum de connexions SQL"
  type        = number
  default     = 100
}

variable "deletion_protection" {
  description = "Protection contre suppression accidentelle"
  type        = bool
  default     = false # FALSE pour pouvoir destroy facilement
}