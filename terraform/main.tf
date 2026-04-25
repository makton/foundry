data "azurerm_client_config" "current" {}

locals {
  _acr_server = var.enable_container_registry ? module.ai_services.container_registry_login_server : null

  # Resolve images: explicit override > ACR-derived URL > hello-world fallback
  _chatbot_ui_image = coalesce(
    var.chatbot_ui_image,
    local._acr_server != null
      ? "${local._acr_server}/chatbot-ui:${var.chatbot_ui_image_tag}"
      : "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest",
  )

  _chatbot_api_image = coalesce(
    var.chatbot_api_image,
    local._acr_server != null
      ? "${local._acr_server}/chatbot-api:${var.chatbot_api_image_tag}"
      : "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest",
  )

  # Inject resolved images into the matching Container App keys
  resolved_api_apps = {
    for k, v in var.api_apps : k => merge(v, {
      image = k == "chatbot-ui"  ? local._chatbot_ui_image
            : k == "chatbot-api" ? local._chatbot_api_image
            : v.image
    })
  }
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_names.resource_group
  location = var.location
  tags     = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  log_analytics_sku            = var.log_analytics_sku
  log_analytics_retention_days = var.log_analytics_retention_days

  tags = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  vnet_address_space              = var.vnet_address_space
  private_endpoints_subnet_prefix = var.private_endpoints_subnet_prefix
  agents_subnet_prefix            = var.agents_subnet_prefix
  training_subnet_prefix          = var.training_subnet_prefix
  container_apps_subnet_prefix    = var.container_apps_subnet_prefix
  agw_subnet_prefix               = var.agw_subnet_prefix
  function_app_subnet_prefix      = var.function_app_subnet_prefix

  private_dns_zones   = local.private_dns_zones
  log_analytics_id    = module.monitoring.log_analytics_workspace_id

  log_analytics_workspace_guid     = module.monitoring.log_analytics_workspace_guid
  log_analytics_workspace_location = module.monitoring.log_analytics_workspace_location

  tags = local.common_tags

  depends_on = [module.monitoring]
}

module "security" {
  source = "./modules/security"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  tenant_id               = data.azurerm_client_config.current.tenant_id
  key_vault_sku           = var.key_vault_sku
  log_analytics_id        = module.monitoring.log_analytics_workspace_id

  private_endpoint_subnet_id  = module.networking.private_endpoints_subnet_id
  private_dns_zone_key_vault  = module.networking.private_dns_zone_ids["key_vault"]

  tags = local.common_tags

  depends_on = [module.networking]
}

module "storage" {
  source = "./modules/storage"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  account_tier             = var.storage_account_tier
  replication_type         = var.storage_replication_type
  log_analytics_id         = module.monitoring.log_analytics_workspace_id

  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_ids = {
    blob  = module.networking.private_dns_zone_ids["blob"]
    file  = module.networking.private_dns_zone_ids["file"]
    queue = module.networking.private_dns_zone_ids["queue"]
    table = module.networking.private_dns_zone_ids["table"]
    dfs   = module.networking.private_dns_zone_ids["dfs"]
  }

  tags = local.common_tags

  depends_on = [module.networking]
}

module "ai_services" {
  source = "./modules/ai_services"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  openai_sku               = var.openai_sku
  openai_model_deployments = var.openai_model_deployments

  enable_ai_search          = var.enable_ai_search
  ai_search_sku             = var.ai_search_sku
  ai_search_replica_count   = var.ai_search_replica_count
  ai_search_partition_count = var.ai_search_partition_count

  enable_container_registry  = var.enable_container_registry
  container_registry_sku     = var.container_registry_sku

  log_analytics_id           = module.monitoring.log_analytics_workspace_id

  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_ids = {
    openai    = module.networking.private_dns_zone_ids["openai"]
    cognitive = module.networking.private_dns_zone_ids["cognitive"]
    search    = module.networking.private_dns_zone_ids["search"]
    acr       = module.networking.private_dns_zone_ids["acr"]
  }

  tags = local.common_tags

  depends_on = [module.networking, module.monitoring]
}

module "ai_foundry" {
  source = "./modules/ai_foundry"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  storage_account_id      = module.storage.storage_account_id
  key_vault_id            = module.security.key_vault_id
  application_insights_id = module.monitoring.application_insights_id
  container_registry_id   = var.enable_container_registry ? module.ai_services.container_registry_id : null

  openai_id               = module.ai_services.openai_id
  openai_endpoint         = module.ai_services.openai_endpoint
  ai_search_id            = var.enable_ai_search ? module.ai_services.ai_search_id : null
  ai_search_endpoint      = var.enable_ai_search ? module.ai_services.ai_search_endpoint : null

  cosmosdb_endpoint      = module.cosmosdb.endpoint
  cosmosdb_id            = module.cosmosdb.account_id
  cosmosdb_database_name = module.cosmosdb.database_name

  managed_network_isolation = var.ai_hub_managed_network_isolation
  ai_projects               = var.ai_projects

  tenant_id                  = data.azurerm_client_config.current.tenant_id
  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_ids = {
    ml_api       = module.networking.private_dns_zone_ids["ml_api"]
    ml_notebooks = module.networking.private_dns_zone_ids["ml_notebooks"]
  }

  ai_hub_owners       = var.ai_hub_owners
  ai_hub_contributors = var.ai_hub_contributors
  ai_hub_readers      = var.ai_hub_readers

  log_analytics_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.monitoring,
    module.security,
    module.storage,
    module.ai_services,
    module.cosmosdb,
  ]
}

module "auth" {
  source = "./modules/auth"

  name             = local.name_prefix
  ui_redirect_uris = var.auth_ui_redirect_uris
}

module "container_apps" {
  source = "./modules/container_apps"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  container_apps_subnet_id = module.networking.container_apps_subnet_id
  vnet_id                  = module.networking.vnet_id

  openai_id       = module.ai_services.openai_id
  openai_endpoint = module.ai_services.openai_endpoint
  ai_search_id    = var.enable_ai_search ? module.ai_services.ai_search_id : null
  ai_search_endpoint = var.enable_ai_search ? module.ai_services.ai_search_endpoint : null

  key_vault_id  = module.security.key_vault_id
  key_vault_uri = module.security.key_vault_uri

  storage_account_id = module.storage.storage_account_id

  container_registry_id           = var.enable_container_registry ? module.ai_services.container_registry_id : null
  container_registry_login_server = var.enable_container_registry ? module.ai_services.container_registry_login_server : null

  cosmosdb_endpoint      = module.cosmosdb.endpoint
  cosmosdb_database_name = module.cosmosdb.database_name

  log_analytics_id                       = module.monitoring.log_analytics_workspace_id
  application_insights_connection_string = module.monitoring.application_insights_connection_string

  internal_load_balancer_enabled = var.container_apps_internal_load_balancer
  zone_redundancy_enabled        = var.container_apps_zone_redundancy

  azure_tenant_id     = module.auth.tenant_id
  azure_api_client_id = module.auth.api_client_id
  azure_ui_client_id  = module.auth.ui_client_id
  azure_api_scope     = module.auth.api_scope

  api_apps = local.resolved_api_apps

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.monitoring,
    module.security,
    module.storage,
    module.ai_services,
  ]
}

module "app_gateway" {
  count  = var.enable_app_gateway ? 1 : 0
  source = "./modules/app_gateway"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  agw_subnet_id = module.networking.agw_subnet_id
  vnet_id       = module.networking.vnet_id

  agw_private_ip       = var.agw_private_ip
  agw_private_hostname = var.agw_private_hostname

  waf_block_api_from_internet = var.waf_block_api_from_internet
  waf_rate_limit_chat_rpm     = var.waf_rate_limit_chat_rpm
  waf_rate_limit_api_rpm      = var.waf_rate_limit_api_rpm

  # Build the backends map by merging routing config with the runtime FQDNs
  # from Container Apps so the AGW always points at the correct endpoints.
  backends = {
    for key, cfg in var.agw_backends : key => {
      fqdn              = module.container_apps.api_app_urls[key]
      path_prefixes     = cfg.path_prefixes
      health_probe_path = cfg.health_probe_path
      backend_port      = cfg.backend_port
      backend_protocol  = cfg.backend_protocol
    }
  }

  default_backend_key = var.agw_default_backend_key

  ssl_certificate_key_vault_secret_id = var.agw_ssl_certificate_key_vault_secret_id
  key_vault_id                        = var.agw_ssl_certificate_key_vault_secret_id != null ? module.security.key_vault_id : null

  custom_hostname        = var.agw_custom_hostname

  waf_mode               = var.agw_waf_mode
  autoscale_min_capacity = var.agw_autoscale_min
  autoscale_max_capacity = var.agw_autoscale_max
  zones                  = var.agw_zones

  log_analytics_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags

  depends_on = [module.container_apps]
}

# ── Function App must be created before CosmosDB RBAC so its principal ID ─────
# exists. CosmosDB data plane roles are assigned by passing the Function App's
# principal ID into the cosmosdb module's data_contributor_principal_ids.

module "function_app" {
  source = "./modules/function_app"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  service_plan_sku       = var.function_app_service_plan_sku
  python_version         = var.function_app_python_version
  zone_balancing_enabled = var.function_app_zone_balancing

  function_app_subnet_id             = module.networking.function_app_subnet_id
  function_app_subnet_address_prefix = var.function_app_subnet_prefix
  private_endpoint_subnet_id         = module.networking.private_endpoints_subnet_id
  private_dns_zone_function_app      = module.networking.private_dns_zone_ids["function_app"]

  # CosmosDB connection (account created in next module — values resolved at plan time)
  cosmosdb_endpoint            = module.cosmosdb.endpoint
  cosmosdb_database_name       = module.cosmosdb.database_name
  cosmosdb_documents_container = "source-documents"
  cosmosdb_chunks_container    = "document-chunks"
  cosmosdb_status_container    = "processing-status"
  cosmosdb_urls_container      = "source-urls"

  openai_endpoint             = module.ai_services.openai_endpoint
  openai_embedding_deployment = var.openai_embedding_deployment

  source_storage_account_name  = module.storage.storage_account_name
  source_storage_container_name = var.source_storage_container_name
  source_storage_account_id    = module.storage.storage_account_id

  ai_search_endpoint   = var.enable_ai_search ? module.ai_services.ai_search_endpoint : null
  ai_search_index_name = var.ai_search_index_name
  ai_search_id         = var.enable_ai_search ? module.ai_services.ai_search_id : null

  key_vault_id  = module.security.key_vault_id
  key_vault_uri = module.security.key_vault_uri

  openai_id = module.ai_services.openai_id

  log_analytics_id                       = module.monitoring.log_analytics_workspace_id
  application_insights_connection_string = module.monitoring.application_insights_connection_string

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.monitoring,
    module.security,
    module.storage,
    module.ai_services,
  ]
}

module "cosmosdb" {
  source = "./modules/cosmosdb"

  name                = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  instance_number     = var.instance_number

  serverless               = var.cosmosdb_serverless
  consistency_level        = var.cosmosdb_consistency_level
  database_name            = var.cosmosdb_database_name
  total_throughput_limit   = var.cosmosdb_serverless ? null : var.cosmosdb_total_throughput_limit
  backup_type              = var.cosmosdb_backup_type
  containers               = var.cosmosdb_containers

  private_endpoint_subnet_id = module.networking.private_endpoints_subnet_id
  private_dns_zone_cosmosdb  = module.networking.private_dns_zone_ids["cosmosdb"]
  function_app_subnet_id     = module.networking.function_app_subnet_id

  log_analytics_id = module.monitoring.log_analytics_workspace_id

  tags = local.common_tags

  depends_on = [
    module.networking,
    module.monitoring,
  ]
}

# ── CosmosDB data-plane RBAC ──────────────────────────────────────────────────
# Kept here (not inside the cosmosdb module) to avoid a circular dependency:
# function_app and ai_foundry both reference module.cosmosdb outputs, so they
# must come after cosmosdb. Assigning RBAC here lets all three modules resolve
# cleanly before these role assignments run.

locals {
  cosmosdb_reader_apps = { for k, v in var.api_apps : k => v if v.needs_cosmosdb_read }
}

resource "azurerm_cosmosdb_sql_role_assignment" "function_app_contributor" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = module.cosmosdb.account_name
  role_definition_id  = "${module.cosmosdb.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.function_app.managed_identity_principal_id
  scope               = module.cosmosdb.account_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "ai_hub_reader" {
  resource_group_name = azurerm_resource_group.main.name
  account_name        = module.cosmosdb.account_name
  role_definition_id  = "${module.cosmosdb.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = module.ai_foundry.ai_hub_principal_id
  scope               = module.cosmosdb.account_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "container_app_readers" {
  for_each = local.cosmosdb_reader_apps

  resource_group_name = azurerm_resource_group.main.name
  account_name        = module.cosmosdb.account_name
  role_definition_id  = "${module.cosmosdb.account_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = module.container_apps.managed_identity_principal_ids[each.key]
  scope               = module.cosmosdb.account_id
}

module "budget" {
  count  = var.enable_budget_alert ? 1 : 0
  source = "./modules/budget"

  name                = local.name_prefix
  instance_number     = var.instance_number
  resource_group_name = azurerm_resource_group.main.name
  resource_group_id   = azurerm_resource_group.main.id

  amount      = var.budget_amount
  start_date  = var.budget_start_date
  alert_emails = var.budget_alert_emails

  tags = local.common_tags
}
