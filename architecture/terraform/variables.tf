# Terraform Variables for Stripe Data Architecture

# GENERAL CONFIGURATION

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "stripe-data"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "Stripe Data Architecture"
    ManagedBy   = "Terraform"
    CostCenter  = "Data Engineering"
    Compliance  = "PCI-DSS,GDPR"
  }
}

# NETWORKING

variable "vnet_address_space" {
  description = "Address space for Virtual Network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for subnets"
  type        = map(string)
  default = {
    sql_subnet      = "10.0.1.0/24"
    synapse_subnet  = "10.0.2.0/24"
    cosmos_subnet   = "10.0.3.0/24"
    adf_subnet      = "10.0.4.0/24"
    ml_subnet       = "10.0.5.0/24"
  }
}

# AZURE SQL DATABASE (OLTP)

variable "sql_server_admin_username" {
  description = "Admin username for Azure SQL Server"
  type        = string
  default     = "sqladmin"
  sensitive   = true
}

variable "sql_server_admin_password" {
  description = "Admin password for Azure SQL Server"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.sql_server_admin_password) >= 16
    error_message = "Password must be at least 16 characters for PCI-DSS compliance."
  }
}

variable "sql_database_sku" {
  description = "SKU for Azure SQL Database"
  type        = map(string)
  default = {
    dev  = "S3"           # Standard 100 DTUs (~$75/month)
    prod = "BC_Gen5_8"    # Business Critical 8 vCores (~$2,920/month)
  }
}

variable "sql_database_max_size_gb" {
  description = "Maximum size of SQL Database in GB"
  type        = number
  default     = 250
}

variable "sql_enable_cdc" {
  description = "Enable Change Data Capture on SQL Database"
  type        = bool
  default     = true
}

variable "sql_backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 35
}

# AZURE SYNAPSE ANALYTICS (OLAP)

variable "synapse_sql_pool_sku" {
  description = "SKU for Synapse SQL Pool (Data Warehouse Units)"
  type        = map(string)
  default = {
    dev  = "DW100c"    # 1000 DWU (~$1,500/month)
    prod = "DW500c"    # 5000 DWU (~$5,840/month)
  }
}

variable "synapse_spark_pool_node_size" {
  description = "Node size for Spark pool"
  type        = string
  default     = "Small"  # Small, Medium, Large
}

variable "synapse_spark_pool_node_count" {
  description = "Number of nodes in Spark pool"
  type        = map(number)
  default = {
    dev  = 3
    prod = 10
  }
}

variable "synapse_spark_autoscale_enabled" {
  description = "Enable autoscaling for Spark pool"
  type        = bool
  default     = true
}

# AZURE COSMOS DB (NoSQL)

variable "cosmos_db_consistency_level" {
  description = "Consistency level for Cosmos DB"
  type        = string
  default     = "Session"
  
  validation {
    condition     = contains(["Strong", "BoundedStaleness", "Session", "ConsistentPrefix", "Eventual"], var.cosmos_db_consistency_level)
    error_message = "Invalid consistency level."
  }
}

variable "cosmos_db_throughput" {
  description = "Throughput (RU/s) for Cosmos DB collections"
  type        = map(object({
    min_throughput = number
    max_throughput = number
  }))
  default = {
    api_logs = {
      min_throughput = 10000
      max_throughput = 50000
    }
    user_sessions = {
      min_throughput = 2000
      max_throughput = 10000
    }
    fraud_features = {
      min_throughput = 5000
      max_throughput = 30000
    }
    webhook_events = {
      min_throughput = 4000
      max_throughput = 20000
    }
  }
}

variable "cosmos_db_enable_multi_region" {
  description = "Enable multi-region replication"
  type        = bool
  default     = true
}

variable "cosmos_db_failover_locations" {
  description = "Failover locations for Cosmos DB"
  type        = list(string)
  default     = ["eastus"]
}

variable "cosmos_db_enable_analytical_storage" {
  description = "Enable analytical storage (Synapse Link)"
  type        = bool
  default     = true
}

# AZURE DATA FACTORY (ETL)

variable "data_factory_git_enabled" {
  description = "Enable Git integration for Data Factory"
  type        = bool
  default     = true
}

variable "data_factory_git_repo_url" {
  description = "Git repository URL for Data Factory"
  type        = string
  default     = ""
}

variable "data_factory_schedule_etl_cron" {
  description = "Cron expression for ETL pipeline schedule"
  type        = string
  default     = "0 0 2 * * *"  # Daily at 02:00 UTC
}

# AZURE STORAGE

variable "storage_account_tier" {
  description = "Storage account tier"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "GRS"  # Geo-Redundant Storage
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_account_replication_type)
    error_message = "Invalid replication type."
  }
}

variable "storage_containers" {
  description = "Storage containers to create"
  type        = list(string)
  default = [
    "staging",
    "raw",
    "processed",
    "backups",
    "logs"
  ]
}

# SECURITY

variable "enable_private_endpoints" {
  description = "Enable private endpoints for all services"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access resources"
  type        = list(string)
  default     = []  # Empty = no public access
}

variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest with customer-managed keys"
  type        = bool
  default     = true
}

variable "key_vault_name" {
  description = "Name of Key Vault for secrets management"
  type        = string
  default     = ""  # Auto-generated if empty
}

# MONITORING


variable "log_analytics_retention_days" {
  description = "Log Analytics retention period in days"
  type        = number
  default     = 90
}

variable "enable_diagnostic_logs" {
  description = "Enable diagnostic logs for all resources"
  type        = bool
  default     = true
}

variable "alert_email_recipients" {
  description = "Email recipients for alerts"
  type        = list(string)
  default     = []
}


# COST MANAGEMENT


variable "enable_cost_management" {
  description = "Enable cost management and budgets"
  type        = bool
  default     = true
}

variable "monthly_budget_amount" {
  description = "Monthly budget amount in USD"
  type        = map(number)
  default = {
    dev  = 5000
    prod = 20000
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds (percentage)"
  type        = list(number)
  default     = [80, 90, 100]
}


# COMPLIANCE


variable "enable_pci_dss_compliance" {
  description = "Enable PCI-DSS compliance features"
  type        = bool
  default     = true
}

variable "enable_gdpr_compliance" {
  description = "Enable GDPR compliance features"
  type        = bool
  default     = true
}

variable "data_residency_region" {
  description = "Data residency requirement (for GDPR)"
  type        = string
  default     = "EU"
}


# DISASTER RECOVERY


variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 35
}

variable "enable_geo_redundancy" {
  description = "Enable geo-redundancy for disaster recovery"
  type        = bool
  default     = true
}

variable "rpo_hours" {
  description = "Recovery Point Objective in hours"
  type        = number
  default     = 1
}

variable "rto_hours" {
  description = "Recovery Time Objective in hours"
  type        = number
  default     = 4
}


# MACHINE LEARNING


variable "enable_azure_ml" {
  description = "Enable Azure Machine Learning workspace"
  type        = bool
  default     = true
}

variable "ml_compute_instance_size" {
  description = "Size of ML compute instance"
  type        = string
  default     = "Standard_DS3_v2"
}

variable "ml_compute_cluster_min_nodes" {
  description = "Minimum nodes in ML compute cluster"
  type        = number
  default     = 0
}

variable "ml_compute_cluster_max_nodes" {
  description = "Maximum nodes in ML compute cluster"
  type        = number
  default     = 4
}