locals {
  func_storage_name = substr(replace("stfunc${var.name}${var.instance_number}", "-", ""), 0, 24)
}

# ── Managed Identity ──────────────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "function_app" {
  name                = "id-func-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ── Function App backing storage ──────────────────────────────────────────────
# Internal use by the Functions host: distributed locks, trigger checkpoints, deployment packages.
# Restricted to the function app VNet integration subnet via network rules + service endpoints.

resource "azurerm_storage_account" "function_app" {
  name                     = local.func_storage_name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled = true
  min_tls_version            = "TLS1_2"

  # Scoped to Function App subnet via service endpoint — not fully public
  public_network_access_enabled = true

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [var.function_app_subnet_id]
    bypass                     = ["AzureServices"]
  }

  tags = var.tags
}

# Grant the Function App identity ownership of its own backing storage
resource "azurerm_role_assignment" "func_storage_blob_owner" {
  scope                = azurerm_storage_account.function_app.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

resource "azurerm_role_assignment" "func_storage_queue_contributor" {
  scope                = azurerm_storage_account.function_app.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

resource "azurerm_role_assignment" "func_storage_table_contributor" {
  scope                = azurerm_storage_account.function_app.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# ── App Service Plan (Premium) ────────────────────────────────────────────────
# Premium EP1+ is required for VNet integration (outbound) and private endpoints (inbound).

resource "azurerm_service_plan" "main" {
  name                   = "asp-func-${var.name}-${var.instance_number}"
  location               = var.location
  resource_group_name    = var.resource_group_name
  os_type                = "Linux"
  sku_name               = var.service_plan_sku
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

# ── Source Blob Container ─────────────────────────────────────────────────────
# The blob trigger watches this container for new documents to import.

resource "azurerm_storage_container" "source_documents" {
  name                  = var.source_storage_container_name
  storage_account_id    = var.source_storage_account_id
  container_access_type = "private"
}

# ── Function App ──────────────────────────────────────────────────────────────

resource "azurerm_linux_function_app" "main" {
  name                = "func-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.main.id

  # Managed-identity access to backing storage (no connection string stored)
  storage_account_name          = azurerm_storage_account.function_app.name
  storage_uses_managed_identity = true

  # Outbound VNet integration — all egress traffic routed into the VNet
  # so private endpoints of CosmosDB, OpenAI, AI Search, etc. are reachable
  virtual_network_subnet_id = var.function_app_subnet_id

  # Inbound: disable public access — accessible only via private endpoint
  public_network_access_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.function_app.id]
  }

  # KV references will use this identity for resolution
  key_vault_reference_identity_id = azurerm_user_assigned_identity.function_app.id

  app_settings = {
    # ── Functions host ──
    FUNCTIONS_EXTENSION_VERSION = "~4"
    FUNCTIONS_WORKER_RUNTIME    = "python"
    WEBSITE_RUN_FROM_PACKAGE    = "1"

    # Use managed identity for all Azure SDK calls within the function code
    AZURE_CLIENT_ID = azurerm_user_assigned_identity.function_app.client_id

    # ── CosmosDB ──
    COSMOSDB_ENDPOINT              = var.cosmosdb_endpoint
    COSMOSDB_DATABASE_NAME         = var.cosmosdb_database_name
    COSMOSDB_DOCUMENTS_CONTAINER   = var.cosmosdb_documents_container
    COSMOSDB_CHUNKS_CONTAINER      = var.cosmosdb_chunks_container
    COSMOSDB_STATUS_CONTAINER      = var.cosmosdb_status_container
    COSMOSDB_URLS_CONTAINER        = var.cosmosdb_urls_container

    # ── Azure OpenAI ──
    AZURE_OPENAI_ENDPOINT             = var.openai_endpoint
    AZURE_OPENAI_EMBEDDING_DEPLOYMENT = var.openai_embedding_deployment

    # ── Source storage (where new documents are uploaded) ──
    SOURCE_STORAGE_ACCOUNT_NAME   = var.source_storage_account_name
    SOURCE_STORAGE_CONTAINER_NAME = var.source_storage_container_name

    # ── AI Search (optional) ──
    AZURE_AI_SEARCH_ENDPOINT   = var.ai_search_endpoint != null ? var.ai_search_endpoint : ""
    AZURE_AI_SEARCH_INDEX_NAME = var.ai_search_index_name

    # ── Key Vault ──
    AZURE_KEY_VAULT_URI = var.key_vault_uri

    # ── Eval queue (Foundry Hosted Agent integration) ──
    # Identity-based queue connection — no connection string stored.
    # __accountName + __clientId tells the Functions host to use the user-assigned
    # managed identity (not system-assigned) when polling the eval-jobs queue.
    # See: https://learn.microsoft.com/azure/azure-functions/functions-bindings-storage-queue#identity-based-connections
    "EvalQueueConnection__accountName" = var.eval_queue_storage_account_name
    "EvalQueueConnection__clientId"    = azurerm_user_assigned_identity.function_app.client_id
    EVAL_JOBS_QUEUE_NAME               = var.eval_jobs_queue_name
    FOUNDRY_AGENT_ENDPOINT             = var.foundry_agent_endpoint
    COSMOSDB_EVAL_CONTAINER            = var.cosmosdb_eval_container

    # ── Monitoring ──
    APPLICATIONINSIGHTS_CONNECTION_STRING = var.application_insights_connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  }

  site_config {
    always_on = true  # Required for Premium plan

    application_stack {
      python_version = var.python_version
    }

    # Route ALL outbound traffic through VNet (not just RFC1918 addresses)
    # This ensures calls to private endpoints resolve correctly
    vnet_route_all_enabled = true

    # Block all inbound on both the main site and the SCM (Kudu) endpoint
    ip_restriction_default_action     = "Deny"
    scm_ip_restriction_default_action = "Deny"
    scm_use_main_ip_restriction       = true
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.func_storage_blob_owner,
    azurerm_role_assignment.func_storage_queue_contributor,
    azurerm_role_assignment.func_storage_table_contributor,
  ]
}

# ── Private Endpoint (inbound access) ────────────────────────────────────────

resource "azurerm_private_endpoint" "function_app" {
  name                = "pe-func-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-func-${var.name}"
    private_connection_resource_id = azurerm_linux_function_app.main.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-func-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_function_app]
  }
}

# ── RBAC: Function App identity → downstream services ────────────────────────

# Read source documents from main storage
resource "azurerm_role_assignment" "source_storage_reader" {
  scope                = var.source_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# Dequeue evaluation jobs from the eval-jobs queue on the main storage account.
# Message Processor = read + delete messages (minimum needed for QueueTrigger).
resource "azurerm_role_assignment" "eval_queue_processor" {
  scope                = var.source_storage_account_id
  role_definition_name = "Storage Queue Data Message Processor"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# Write processed data to CosmosDB (data plane RBAC via azapi — see note below)
# Cosmos DB data plane roles are assigned in the cosmosdb module by passing this principal_id.

# Call OpenAI embedding API
resource "azurerm_role_assignment" "openai_user" {
  scope                = var.openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# Push chunks to AI Search index
resource "azurerm_role_assignment" "search_index_contributor" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

resource "azurerm_role_assignment" "search_service_contributor" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# Read secrets from Key Vault (for any runtime secret references)
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.function_app.principal_id
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "diag-func-${var.name}"
  target_resource_id         = azurerm_linux_function_app.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "FunctionAppLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
