output "resource_group_name" {
  description = "Name of the primary resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the primary resource group"
  value       = azurerm_resource_group.main.id
}

output "vnet_id" {
  description = "Virtual network ID"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = module.networking.vnet_name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID"
  value       = module.monitoring.log_analytics_workspace_id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.monitoring.application_insights_connection_string
  sensitive   = true
}

output "key_vault_id" {
  description = "Key Vault resource ID"
  value       = module.security.key_vault_id
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.security.key_vault_uri
}

output "storage_account_id" {
  description = "Storage account resource ID"
  value       = module.storage.storage_account_id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = module.storage.storage_account_name
}

output "openai_id" {
  description = "Azure OpenAI resource ID"
  value       = module.ai_services.openai_id
}

output "openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  value       = module.ai_services.openai_endpoint
  sensitive   = true
}

output "ai_search_id" {
  description = "Azure AI Search resource ID"
  value       = var.enable_ai_search ? module.ai_services.ai_search_id : null
}

output "ai_search_endpoint" {
  description = "Azure AI Search endpoint URL"
  value       = var.enable_ai_search ? module.ai_services.ai_search_endpoint : null
  sensitive   = true
}

output "container_registry_login_server" {
  description = "Container Registry login server"
  value       = var.enable_container_registry ? module.ai_services.container_registry_login_server : null
}

output "ai_hub_id" {
  description = "AI Hub resource ID"
  value       = module.ai_foundry.ai_hub_id
}

output "ai_hub_name" {
  description = "AI Hub name"
  value       = module.ai_foundry.ai_hub_name
}

output "ai_project_ids" {
  description = "Map of AI project names to resource IDs"
  value       = module.ai_foundry.ai_project_ids
}

output "ai_hub_principal_id" {
  description = "AI Hub system-assigned managed identity principal ID"
  value       = module.ai_foundry.ai_hub_principal_id
}

# ── Container Apps ────────────────────────────────────────────────────────────

output "container_apps_environment_id" {
  description = "Container Apps Environment resource ID"
  value       = module.container_apps.environment_id
}

output "container_apps_environment_name" {
  description = "Container Apps Environment name"
  value       = module.container_apps.environment_name
}

output "container_apps_environment_default_domain" {
  description = "Default domain for the Container Apps Environment (used for DNS)"
  value       = module.container_apps.environment_default_domain
}

output "container_apps_environment_static_ip" {
  description = "Static IP of the internal load balancer for private DNS configuration"
  value       = module.container_apps.environment_static_ip
}

output "container_apps_managed_identity_client_ids" {
  description = "Map of app name to managed identity client ID — one identity per Container App"
  value       = module.container_apps.managed_identity_client_ids
}

output "api_app_urls" {
  description = "Map of API app names to their ingress FQDNs"
  value       = module.container_apps.api_app_urls
}

# ── Application Gateway ───────────────────────────────────────────────────────

output "agw_public_ip" {
  description = "Public IP address of the Application Gateway (point your DNS A record here)"
  value       = var.enable_app_gateway ? module.app_gateway[0].public_ip_address : null
}

output "agw_id" {
  description = "Application Gateway resource ID"
  value       = var.enable_app_gateway ? module.app_gateway[0].agw_id : null
}

output "waf_policy_id" {
  description = "WAF policy resource ID"
  value       = var.enable_app_gateway ? module.app_gateway[0].waf_policy_id : null
}

# ── CosmosDB ──────────────────────────────────────────────────────────────────

output "cosmosdb_endpoint" {
  description = "CosmosDB account endpoint"
  value       = module.cosmosdb.endpoint
  sensitive   = true
}

output "cosmosdb_account_name" {
  description = "CosmosDB account name"
  value       = module.cosmosdb.account_name
}

output "cosmosdb_database_name" {
  description = "CosmosDB database name"
  value       = module.cosmosdb.database_name
}

output "cosmosdb_container_names" {
  description = "Map of container logical names to CosmosDB container names"
  value       = module.cosmosdb.container_names
}

# ── Function App ──────────────────────────────────────────────────────────────

output "function_app_name" {
  description = "Import Function App name"
  value       = module.function_app.function_app_name
}

output "function_app_hostname" {
  description = "Import Function App hostname (accessible only via private endpoint)"
  value       = module.function_app.function_app_hostname
}

output "function_app_principal_id" {
  description = "Function App managed identity principal ID"
  value       = module.function_app.managed_identity_principal_id
}

# ── Budget ────────────────────────────────────────────────────────────────────

output "budget_id" {
  description = "Cost Management budget resource ID (null when enable_budget_alert = false)"
  value       = var.enable_budget_alert ? module.budget[0].budget_id : null
}

output "budget_action_group_id" {
  description = "Monitor Action Group resource ID for budget alerts — add other alert rules here to reuse the notification channel"
  value       = var.enable_budget_alert ? module.budget[0].action_group_id : null
}
