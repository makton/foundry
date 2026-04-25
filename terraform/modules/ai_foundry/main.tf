# ── AI Hub (Azure AI Foundry resource) ───────────────────────────────────────
# The AI Hub is the top-level governance resource in Azure AI Foundry.
# It is backed by azurerm_machine_learning_workspace with kind = "Hub".

resource "azurerm_machine_learning_workspace" "hub" {
  name                    = "aih-${var.name}-${var.instance_number}"
  location                = var.location
  resource_group_name     = var.resource_group_name
  kind                    = "Hub"
  sku_name                = "Basic"
  friendly_name           = "AI Hub — ${var.name}"
  description             = "Azure AI Foundry Hub for ${var.name}"

  storage_account_id      = var.storage_account_id
  key_vault_id            = var.key_vault_id
  application_insights_id = var.application_insights_id
  container_registry_id   = var.container_registry_id

  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  managed_network {
    isolation_mode = var.managed_network_isolation
  }

  tags = var.tags
}

# ── AI Projects ───────────────────────────────────────────────────────────────
# Each project is a development isolation boundary scoped to the hub.

resource "azurerm_machine_learning_workspace" "projects" {
  for_each = var.ai_projects

  name                = "aip-${var.name}-${each.key}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Project"
  sku_name            = "Basic"
  friendly_name       = each.value.display_name != "" ? each.value.display_name : each.key
  description         = each.value.description

  # Projects inherit storage, key vault, and insights from the hub
  storage_account_id      = var.storage_account_id
  key_vault_id            = var.key_vault_id
  application_insights_id = var.application_insights_id

  hub_id = azurerm_machine_learning_workspace.hub.id

  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── Hub Connections ───────────────────────────────────────────────────────────
# Connections make Azure services discoverable and usable within AI Foundry.
# Using azapi_resource because azurerm doesn't expose workspace connections yet.

resource "azapi_resource" "hub_connection_openai" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-10-01"
  name      = "connection-openai"
  parent_id = azurerm_machine_learning_workspace.hub.id

  body = {
    properties = {
      category      = "AzureOpenAI"
      authType      = "AAD"
      isSharedToAll = true
      target        = var.openai_endpoint
      metadata = {
        ApiType    = "Azure"
        ResourceId = var.openai_id
      }
    }
  }

  response_export_values = ["*"]
}

resource "azapi_resource" "hub_connection_ai_search" {
  count = var.ai_search_id != null ? 1 : 0

  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-10-01"
  name      = "connection-ai-search"
  parent_id = azurerm_machine_learning_workspace.hub.id

  body = {
    properties = {
      category      = "CognitiveSearch"
      authType      = "AAD"
      isSharedToAll = true
      target        = var.ai_search_endpoint
      metadata = {
        ResourceId = var.ai_search_id
      }
    }
  }

  response_export_values = ["*"]
}

resource "azapi_resource" "hub_connection_cosmosdb" {
  type      = "Microsoft.MachineLearningServices/workspaces/connections@2024-10-01"
  name      = "connection-cosmosdb"
  parent_id = azurerm_machine_learning_workspace.hub.id

  body = {
    properties = {
      category      = "CosmosDb"
      authType      = "AAD"
      isSharedToAll = true
      target        = var.cosmosdb_endpoint
      metadata = {
        ResourceId   = var.cosmosdb_id
        DatabaseName = var.cosmosdb_database_name
      }
    }
  }

  response_export_values = ["*"]
}

# ── Hub Private Endpoint ──────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "hub" {
  name                = "pe-aih-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-aih-${var.name}"
    private_connection_resource_id = azurerm_machine_learning_workspace.hub.id
    subresource_names              = ["amlworkspace"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "pdns-aih-${var.name}"
    private_dns_zone_ids = [
      var.private_dns_zone_ids["ml_api"],
      var.private_dns_zone_ids["ml_notebooks"],
    ]
  }
}

# ── RBAC ──────────────────────────────────────────────────────────────────────
# Azure AI Foundry built-in roles:
#   - "Azure AI Administrator"  → manage hub settings, deploy models, audit
#   - "Azure AI Developer"      → build agents, run evaluations
#   - "Reader"                  → read-only visibility

resource "azurerm_role_assignment" "hub_owners" {
  for_each = toset(var.ai_hub_owners)

  scope                = azurerm_machine_learning_workspace.hub.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "hub_contributors" {
  for_each = toset(var.ai_hub_contributors)

  scope                = azurerm_machine_learning_workspace.hub.id
  role_definition_name = "Azure AI Developer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "hub_readers" {
  for_each = toset(var.ai_hub_readers)

  scope                = azurerm_machine_learning_workspace.hub.id
  role_definition_name = "Reader"
  principal_id         = each.value
}

# ── Hub Managed Identity RBAC on connected services ──────────────────────────
# The hub's system-assigned identity needs access to read from connected resources.

resource "azurerm_role_assignment" "hub_openai_user" {
  scope                = var.openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

resource "azurerm_role_assignment" "hub_search_index_reader" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

resource "azurerm_role_assignment" "hub_search_service_contributor" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_machine_learning_workspace.hub.identity[0].principal_id
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "hub" {
  name                       = "diag-aih-${var.name}"
  target_resource_id         = azurerm_machine_learning_workspace.hub.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "ComputeInstanceEvent"
  }
  enabled_log {
    category = "DataLabelingEvent"
  }
  enabled_log {
    category = "DeploymentEventACI"
  }
  enabled_log {
    category = "DeploymentEventAKS"
  }
  enabled_log {
    category = "ModelsChangeEvent"
  }
  enabled_log {
    category = "RunEvent"
  }
  enabled_log {
    category = "EnvironmentChangeEvent"
  }

  metric {
    category = "AllMetrics"
  }
}
