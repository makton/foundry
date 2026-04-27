# ── Per-resource CMK identities ───────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "openai_cmk" {
  name                = "id-oai-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "openai_cmk_crypto_user" {
  scope                = var.cmk_key_ids["openai"]
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.openai_cmk.principal_id
}

resource "azurerm_user_assigned_identity" "search_cmk" {
  count = var.enable_ai_search ? 1 : 0

  name                = "id-srch-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "search_cmk_crypto_user" {
  count = var.enable_ai_search ? 1 : 0

  scope                = var.cmk_key_ids["search"]
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.search_cmk[0].principal_id
}

resource "azurerm_user_assigned_identity" "acr_cmk" {
  count = var.enable_container_registry ? 1 : 0

  name                = "id-acr-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_cmk_crypto_user" {
  count = var.enable_container_registry ? 1 : 0

  scope                = var.cmk_key_ids["acr"]
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.acr_cmk[0].principal_id
}

# ── Azure OpenAI ──────────────────────────────────────────────────────────────

resource "azurerm_cognitive_account" "openai" {
  name                = "oai-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "OpenAI"
  sku_name            = var.openai_sku

  public_network_access_enabled = false

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.openai_cmk.id]
  }

  customer_managed_key {
    key_vault_key_id   = var.cmk_key_versionless_ids["openai"]
    identity_client_id = azurerm_user_assigned_identity.openai_cmk.client_id
  }

  network_acls {
    default_action = "Deny"
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.openai_cmk_crypto_user]
}

resource "azurerm_cognitive_deployment" "openai_models" {
  for_each = var.openai_model_deployments

  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.scale_type
    capacity = each.value.capacity   # K TPM — e.g. 50 = 50 000 tokens per minute
  }

  rai_policy_name            = each.value.rai_policy
  dynamic_throttling_enabled = each.value.dynamic_throttling_enabled
  version_upgrade_option     = each.value.version_upgrade_option
}

resource "azurerm_private_endpoint" "openai" {
  name                = "pe-oai-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-oai-${var.name}"
    private_connection_resource_id = azurerm_cognitive_account.openai.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdns-oai-${var.name}"
    # OpenAI uses both openai and cognitiveservices DNS zones
    private_dns_zone_ids = [
      var.private_dns_zone_ids["openai"],
      var.private_dns_zone_ids["cognitive"],
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "openai" {
  name                       = "diag-oai-${var.name}"
  target_resource_id         = azurerm_cognitive_account.openai.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "Audit"
  }
  enabled_log {
    category = "RequestResponse"
  }
  enabled_log {
    category = "Trace"
  }
  metric {
    category = "AllMetrics"
  }
}

# ── Azure AI Search ───────────────────────────────────────────────────────────

resource "azurerm_search_service" "main" {
  count = var.enable_ai_search ? 1 : 0

  name                = "srch-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.ai_search_sku
  replica_count       = var.ai_search_replica_count
  partition_count     = var.ai_search_partition_count

  public_network_access_enabled   = false
  local_authentication_enabled    = false  # Enforce Entra ID only
  authentication_failure_mode     = "http403"
  semantic_search_sku             = var.ai_search_sku == "standard" || var.ai_search_sku == "standard2" || var.ai_search_sku == "standard3" ? "standard" : null

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.search_cmk[0].id]
  }

  customer_managed_key {
    key_vault_key_id   = var.cmk_key_versionless_ids["search"]
    identity_client_id = azurerm_user_assigned_identity.search_cmk[0].client_id
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.search_cmk_crypto_user]
}

resource "azurerm_private_endpoint" "ai_search" {
  count = var.enable_ai_search ? 1 : 0

  name                = "pe-srch-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-srch-${var.name}"
    private_connection_resource_id = azurerm_search_service.main[0].id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-srch-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_ids["search"]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "ai_search" {
  count = var.enable_ai_search ? 1 : 0

  name                       = "diag-srch-${var.name}"
  target_resource_id         = azurerm_search_service.main[0].id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "OperationLogs"
  }
  metric {
    category = "AllMetrics"
  }
}

# ── Azure Container Registry ──────────────────────────────────────────────────

resource "azurerm_container_registry" "main" {
  count = var.enable_container_registry ? 1 : 0

  name                = "acr${replace(var.name, "-", "")}${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.container_registry_sku

  public_network_access_enabled = false
  admin_enabled                 = false

  # Zone redundancy requires Premium SKU
  zone_redundancy_enabled = var.container_registry_sku == "Premium" ? true : false

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.acr_cmk[0].id]
  }

  encryption {
    key_vault_key_id   = var.cmk_key_versionless_ids["acr"]
    identity_client_id = azurerm_user_assigned_identity.acr_cmk[0].client_id
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.acr_cmk_crypto_user]
}

resource "azurerm_private_endpoint" "acr" {
  count = var.enable_container_registry ? 1 : 0

  name                = "pe-acr-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr-${var.name}"
    private_connection_resource_id = azurerm_container_registry.main[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-acr-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_ids["acr"]]
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.enable_container_registry ? 1 : 0

  name                       = "diag-acr-${var.name}"
  target_resource_id         = azurerm_container_registry.main[0].id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }
  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }
  metric {
    category = "AllMetrics"
  }
}
