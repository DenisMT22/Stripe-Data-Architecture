# Main Terraform Configuration for Stripe Data Architecture

# LOCAL VARIABLES

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  
  common_tags = merge(var.tags, {
    Environment = var.environment
    DeployedAt  = timestamp()
  })
  
  resource_names = {
    resource_group        = "${local.resource_prefix}-rg"
    vnet                  = "${local.resource_prefix}-vnet"
    sql_server            = "${local.resource_prefix}-sql"
    sql_database          = "stripe_oltp_db"
    synapse_workspace     = "${local.resource_prefix}-synapse"
    synapse_sql_pool      = "stripe_dw"
    cosmos_account        = "${local.resource_prefix}-cosmos"
    cosmos_database       = "stripe_nosql_db"
    data_factory          = "${local.resource_prefix}-adf"
    storage_account       = replace("${local.resource_prefix}sa", "-", "")  # No hyphens allowed
    key_vault             = "${local.resource_prefix}-kv"
    log_analytics         = "${local.resource_prefix}-logs"
    ml_workspace          = "${local.resource_prefix}-ml"
  }
}

# RESOURCE GROUP

resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}

# NETWORKING MODULE

module "networking" {
  source = "./modules/networking.tf"
  
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  vnet_name           = local.resource_names.vnet
  address_space       = var.vnet_address_space
  subnet_prefixes     = var.subnet_address_prefixes
  tags                = local.common_tags
}

# SECURITY MODULE (Key Vault + Managed Identities)

module "security" {
  source = "./modules/security.tf"
  
  resource_group_name              = azurerm_resource_group.main.name
  location                         = azurerm_resource_group.main.location
  key_vault_name                   = local.resource_names.key_vault
  enable_private_endpoints         = var.enable_private_endpoints
  subnet_id                        = module.networking.subnet_ids["sql_subnet"]
  enable_advanced_threat_protection = var.enable_advanced_threat_protection
  tags                             = local.common_tags
  
  secrets = {
    sql-admin-username = var.sql_server_admin_username
    sql-admin-password = var.sql_server_admin_password
  }
}

# AZURE SQL DATABASE MODULE (OLTP)

module "sql_database" {
  source = "./modules/sql_database.tf"
  
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  sql_server_name        = local.resource_names.sql_server
  sql_database_name      = local.resource_names.sql_database
  admin_username         = var.sql_server_admin_username
  admin_password         = var.sql_server_admin_password
  sku_name               = var.sql_database_sku[var.environment]
  max_size_gb            = var.sql_database_max_size_gb
  enable_cdc             = var.sql_enable_cdc
  backup_retention_days  = var.sql_backup_retention_days
  enable_private_endpoint = var.enable_private_endpoints
  subnet_id              = module.networking.subnet_ids["sql_subnet"]
  tags                   = local.common_tags
  
  depends_on = [module.networking, module.security]
}

# AZURE SYNAPSE ANALYTICS MODULE (OLAP)

module "synapse_analytics" {
  source = "./modules/synapse_analytics.tf"
  
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  synapse_workspace_name      = local.resource_names.synapse_workspace
  synapse_sql_pool_name       = local.resource_names.synapse_sql_pool
  sql_pool_sku                = var.synapse_sql_pool_sku[var.environment]
  storage_account_id          = azurerm_storage_account.datalake.id
  spark_pool_node_size        = var.synapse_spark_pool_node_size
  spark_pool_node_count       = var.synapse_spark_pool_node_count[var.environment]
  spark_autoscale_enabled     = var.synapse_spark_autoscale_enabled
  enable_private_endpoint     = var.enable_private_endpoints
  subnet_id                   = module.networking.subnet_ids["synapse_subnet"]
  tags                        = local.common_tags
  
  depends_on = [module.networking, azurerm_storage_account.datalake]
}

# AZURE COSMOS DB MODULE (NoSQL)

module "cosmos_db" {
  source = "./modules/cosmos_db.tf"
  
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  cosmos_account_name           = local.resource_names.cosmos_account
  cosmos_database_name          = local.resource_names.cosmos_database
  consistency_level             = var.cosmos_db_consistency_level
  throughput_config             = var.cosmos_db_throughput
  enable_multi_region           = var.cosmos_db_enable_multi_region
  failover_locations            = var.cosmos_db_failover_locations
  enable_analytical_storage     = var.cosmos_db_enable_analytical_storage
  enable_private_endpoint       = var.enable_private_endpoints
  subnet_id                     = module.networking.subnet_ids["cosmos_subnet"]
  tags                          = local.common_tags
  
  depends_on = [module.networking]
}

# AZURE DATA FACTORY MODULE (ETL)

module "data_factory" {
  source = "./modules/data_factory.tf"
  
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  data_factory_name         = local.resource_names.data_factory
  enable_git                = var.data_factory_git_enabled
  git_repo_url              = var.data_factory_git_repo_url
  enable_private_endpoint   = var.enable_private_endpoints
  subnet_id                 = module.networking.subnet_ids["adf_subnet"]
  tags                      = local.common_tags
  
  sql_connection_string     = module.sql_database.connection_string
  synapse_connection_string = module.synapse_analytics.connection_string
  cosmos_connection_string  = module.cosmos_db.connection_string
  storage_connection_string = azurerm_storage_account.datalake.primary_connection_string
  
  depends_on = [
    module.sql_database,
    module.synapse_analytics,
    module.cosmos_db,
    azurerm_storage_account.datalake
  ]
}

# AZURE STORAGE ACCOUNT (Data Lake Gen2)

resource "azurerm_storage_account" "datalake" {
  name                     = local.resource_names.storage_account
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  is_hns_enabled           = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  tags = local.common_tags
}

resource "azurerm_storage_container" "containers" {
  for_each = toset(var.storage_containers)
  name                 = each.value
  storage_account_id   = azurerm_storage_account.datalake.id
  container_access_type = "private"
}

# LOG ANALYTICS WORKSPACE (Monitoring)

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.resource_names.log_analytics
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.common_tags
}

# DIAGNOSTIC SETTINGS (All resources send logs to Log Analytics)

resource "azurerm_monitor_diagnostic_setting" "sql_database" {
  count = var.enable_diagnostic_logs ? 1 : 0
  name                       = "sql-diagnostics"
  target_resource_id         = module.sql_database.database_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "SQLInsights"
  }

  enabled_log {
    category = "QueryStoreRuntimeStatistics"
  }
  # Bloc `metric` déprécié supprimé !
}

resource "azurerm_monitor_diagnostic_setting" "synapse" {
  count = var.enable_diagnostic_logs ? 1 : 0

  name                       = "synapse-diagnostics"
  target_resource_id         = module.synapse_analytics.workspace_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "SynapseRbacOperations"
  }

  enabled_log {
    category = "GatewayApiRequests"
  }
  # Bloc `metric` déprécié supprimé !
}

# AZURE MACHINE LEARNING (Optional)

resource "azurerm_machine_learning_workspace" "main" {
  count = var.enable_azure_ml ? 1 : 0

  name                    = local.resource_names.ml_workspace
  resource_group_name     = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  application_insights_id = azurerm_application_insights.main[0].id
  key_vault_id            = module.security.key_vault_id
  storage_account_id      = azurerm_storage_account.datalake.id

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

resource "azurerm_application_insights" "main" {
  count = var.enable_azure_ml ? 1 : 0

  name                = "${local.resource_prefix}-appinsights"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id

  tags = local.common_tags
}

# COST MANAGEMENT BUDGET

resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.enable_cost_management ? 1 : 0

  name              = "${local.resource_prefix}-budget"
  resource_group_id = azurerm_resource_group.main.id

  amount     = var.monthly_budget_amount[var.environment]
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.alert_email_recipients
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.alert_email_recipients
  }
}
