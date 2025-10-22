# Terraform Outputs for Stripe Data Architecture

# RESOURCE GROUP

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# NETWORKING

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = module.networking.vnet_id
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = module.networking.subnet_ids
}

# AZURE SQL DATABASE (OLTP)

output "sql_server_fqdn" {
  description = "Fully qualified domain name of SQL Server"
  value       = module.sql_database.sql_server_fqdn
}

output "sql_database_name" {
  description = "Name of SQL Database"
  value       = module.sql_database.database_name
}

output "sql_database_id" {
  description = "ID of SQL Database"
  value       = module.sql_database.database_id
  sensitive   = true
}

output "sql_connection_string" {
  description = "Connection string for SQL Database (without password)"
  value       = "Server=tcp:${module.sql_database.sql_server_fqdn},1433;Database=${module.sql_database.database_name};User ID=${var.sql_server_admin_username}"
  sensitive   = true
}

# AZURE SYNAPSE ANALYTICS (OLAP)

output "synapse_workspace_name" {
  description = "Name of Synapse workspace"
  value       = module.synapse_analytics.workspace_name
}

output "synapse_sql_endpoint" {
  description = "SQL endpoint for Synapse Analytics"
  value       = module.synapse_analytics.sql_endpoint
}

output "synapse_dev_endpoint" {
  description = "Dev endpoint for Synapse workspace"
  value       = module.synapse_analytics.dev_endpoint
}

output "synapse_sql_pool_name" {
  description = "Name of Synapse SQL Pool"
  value       = module.synapse_analytics.sql_pool_name
}


# AZURE COSMOS DB (NoSQL)

output "cosmos_account_name" {
  description = "Name of Cosmos DB account"
  value       = module.cosmos_db.account_name
}

output "cosmos_endpoint" {
  description = "Endpoint URL for Cosmos DB"
  value       = module.cosmos_db.endpoint
}

output "cosmos_primary_key" {
  description = "Primary key for Cosmos DB"
  value       = module.cosmos_db.primary_key
  sensitive   = true
}

output "cosmos_connection_string" {
  description = "Connection string for Cosmos DB"
  value       = module.cosmos_db.connection_string
  sensitive   = true
}

output "cosmos_database_name" {
  description = "Name of Cosmos DB database"
  value       = module.cosmos_db.database_name
}

# AZURE DATA FACTORY (ETL)

output "data_factory_name" {
  description = "Name of Data Factory"
  value       = module.data_factory.data_factory_name
}

output "data_factory_id" {
  description = "ID of Data Factory"
  value       = module.data_factory.data_factory_id
}

# STORAGE ACCOUNT

output "storage_account_name" {
  description = "Name of Storage Account"
  value       = azurerm_storage_account.datalake.name
}

output "storage_account_id" {
  description = "ID of Storage Account"
  value       = azurerm_storage_account.datalake.id
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint"
  value       = azurerm_storage_account.datalake.primary_blob_endpoint
}

output "storage_containers" {
  description = "List of storage containers"
  value       = [for c in azurerm_storage_container.containers : c.name]
}

# SECURITY

output "key_vault_name" {
  description = "Name of Key Vault"
  value       = module.security.key_vault_name
}

output "key_vault_uri" {
  description = "URI of Key Vault"
  value       = module.security.key_vault_uri
}

# MONITORING

output "log_analytics_workspace_id" {
  description = "ID of Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

# MACHINE LEARNING (if enabled)

output "ml_workspace_name" {
  description = "Name of Azure ML workspace"
  value       = var.enable_azure_ml ? azurerm_machine_learning_workspace.main[0].name : null
}

output "ml_workspace_id" {
  description = "ID of Azure ML workspace"
  value       = var.enable_azure_ml ? azurerm_machine_learning_workspace.main[0].id : null
  sensitive   = true
}

# CONNECTION STRINGS (for application configuration)

output "connection_strings" {
  description = "Connection strings for all services (use with caution)"
  value = {
    sql_database = "Server=tcp:${module.sql_database.sql_server_fqdn},1433;Database=${module.sql_database.database_name};Authentication=Active Directory Managed Identity"
    synapse      = module.synapse_analytics.sql_endpoint
    cosmos_db    = module.cosmos_db.endpoint
    storage      = azurerm_storage_account.datalake.primary_blob_endpoint
  }
  sensitive = true
}

# DEPLOYMENT SUMMARY

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment         = var.environment
    location            = var.location
    resource_group      = azurerm_resource_group.main.name
    sql_database_sku    = var.sql_database_sku[var.environment]
    synapse_sku         = var.synapse_sql_pool_sku[var.environment]
    cosmos_enabled      = true
    ml_enabled          = var.enable_azure_ml
    private_endpoints   = var.enable_private_endpoints
    multi_region_cosmos = var.cosmos_db_enable_multi_region
  }
}

# COST ESTIMATION

output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = var.environment == "prod" ? {
    sql_database      = 2920
    synapse_analytics = 5840
    cosmos_db         = 7920
    data_factory      = 350
    storage           = 450
    monitoring        = 280
    networking        = 240
    total             = 18000
  } : {
    sql_database      = 75
    synapse_analytics = 1500
    cosmos_db         = 2000
    data_factory      = 100
    storage           = 150
    monitoring        = 80
    networking        = 95
    total             = 4500
  }
}

# QUICK START COMMANDS

output "quick_start_commands" {
  description = "Commands to quickly connect to deployed resources"
  value = {
    connect_to_sql = "sqlcmd -S ${module.sql_database.sql_server_fqdn} -d ${module.sql_database.database_name} -U ${var.sql_server_admin_username} -P '<password>'"
    
    connect_to_synapse = "sqlcmd -S ${module.synapse_analytics.sql_endpoint} -d ${module.synapse_analytics.sql_pool_name} -U sqladmin -P '<password>'"
    
    connect_to_cosmos_cli = "az cosmosdb database show --name ${module.cosmos_db.database_name} --account-name ${module.cosmos_db.account_name} --resource-group ${azurerm_resource_group.main.name}"
    
    open_synapse_studio = "https://${module.synapse_analytics.workspace_name}.dev.azuresynapse.net"
    
    open_data_factory = "https://adf.azure.com/en/home?factory=%2Fsubscriptions%2F<subscription-id>%2FresourceGroups%2F${azurerm_resource_group.main.name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${module.data_factory.data_factory_name}"
  }
}

# NEXT STEPS

output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value = [
    "1. Run CDC setup script: sqlcmd -S ${module.sql_database.sql_server_fqdn} -d ${module.sql_database.database_name} -i ../pipelines/scripts/setup_cdc.sql",
    "2. Deploy OLTP schema: sqlcmd -i ../../models/oltp/schema.sql",
    "3. Deploy OLAP schema: sqlcmd -S ${module.synapse_analytics.sql_endpoint} -i ../../models/olap/schema.sql",
    "4. Import Data Factory pipelines: az datafactory pipeline create --factory-name ${module.data_factory.data_factory_name} --name etl_oltp_to_olap --pipeline @../pipelines/adf/etl_oltp_to_olap.json",
    "5. Configure Cosmos DB collections: Use Azure Portal or create via SDK",
    "6. Run initial data load: az datafactory pipeline create-run --factory-name ${module.data_factory.data_factory_name} --name etl_oltp_to_olap",
    "7. Verify monitoring: Open Log Analytics workspace in Azure Portal"
  ]
}
