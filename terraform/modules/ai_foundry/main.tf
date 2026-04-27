# ── AI Hub (Azure AI Foundry resource) ───────────────────────────────────────
# The AI Hub is backed by azurerm_cognitive_account with kind = "AIServices".

resource "azurerm_user_assigned_identity" "cmk" {
  name                = "id-aif-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk_crypto_user" {
  scope                = var.cmk_key_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk.principal_id
}

resource "azurerm_cognitive_account" "hub" {
  name                = "aif-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "AIServices"
  sku_name            = "AIServices"

  custom_subdomain_name         = "aif-${var.name}-${var.instance_number}"
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
  }

  network_injection {
    subnet_id = var.agents_subnet_id
    scenario  = "agent"
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cmk.id]
  }

  customer_managed_key {
    key_vault_key_id   = var.cmk_key_versionless_id
    identity_client_id = azurerm_user_assigned_identity.cmk.client_id
  }

  tags = var.tags

  depends_on = [azurerm_role_assignment.cmk_crypto_user]
}

# ── AI Projects ───────────────────────────────────────────────────────────────
# Each project is a development isolation boundary scoped to the hub.

resource "azurerm_cognitive_account_project" "projects" {
  for_each = var.ai_projects

  name                = "aip-${var.name}-${each.key}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name != "" ? each.value.display_name : each.key
  description         = each.value.description

  cognitive_account_id = azurerm_cognitive_account.hub.id

  public_network_access_enabled = false

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── Hub Connections ───────────────────────────────────────────────────────────
# Connections make Azure services discoverable and usable within AI Foundry.

resource "azapi_resource" "hub_connection_openai" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2024-10-01"
  name      = "connection-openai"
  parent_id = azurerm_cognitive_account.hub.id

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

  type      = "Microsoft.CognitiveServices/accounts/connections@2024-10-01"
  name      = "connection-ai-search"
  parent_id = azurerm_cognitive_account.hub.id

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
  type      = "Microsoft.CognitiveServices/accounts/connections@2024-10-01"
  name      = "connection-cosmosdb"
  parent_id = azurerm_cognitive_account.hub.id

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

# ── RBAC ──────────────────────────────────────────────────────────────────────
# Azure AI Foundry built-in roles:
#   - "Azure AI Administrator"  → manage hub settings, deploy models, audit
#   - "Azure AI Developer"      → build agents, run evaluations
#   - "Reader"                  → read-only visibility

resource "azurerm_role_assignment" "hub_owners" {
  for_each = toset(var.ai_hub_owners)

  scope                = azurerm_cognitive_account.hub.id
  role_definition_name = "Azure AI Administrator"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "hub_contributors" {
  for_each = toset(var.ai_hub_contributors)

  scope                = azurerm_cognitive_account.hub.id
  role_definition_name = "Azure AI Developer"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "hub_readers" {
  for_each = toset(var.ai_hub_readers)

  scope                = azurerm_cognitive_account.hub.id
  role_definition_name = "Reader"
  principal_id         = each.value
}

# ── Per-project team RBAC ─────────────────────────────────────────────────────
# Three Entra security groups per project (admins/developers/readers).
# RBAC is scoped to the project workspace — teams only have access to their project.

locals {
  project_team_roles = merge([
    for proj_key, proj in var.ai_projects : {
      "${proj_key}:admins" = {
        project = proj_key
        role    = "admins"
        members = proj.admin_members
        rbac    = "Azure AI Administrator"
      }
      "${proj_key}:developers" = {
        project = proj_key
        role    = "developers"
        members = proj.developer_members
        rbac    = "Azure AI Developer"
      }
      "${proj_key}:readers" = {
        project = proj_key
        role    = "readers"
        members = proj.reader_members
        rbac    = "Reader"
      }
    }
  ]...)
}

resource "azuread_group" "project_team" {
  for_each = local.project_team_roles

  display_name     = "grp-${var.name}-${var.instance_number}-${each.value.project}-${each.value.role}"
  security_enabled = true
  description      = "AI Foundry ${each.value.project} project ${each.value.role}"
  members          = each.value.members
}

resource "azurerm_role_assignment" "project_team" {
  for_each = local.project_team_roles

  scope                = azurerm_cognitive_account_project.projects[each.value.project].id
  role_definition_name = each.value.rbac
  principal_id         = azuread_group.project_team[each.key].object_id
}

# ── Hub Managed Identity RBAC on connected services ──────────────────────────
# The hub's system-assigned identity needs access to read from connected resources.

resource "azurerm_role_assignment" "hub_openai_user" {
  scope                = var.openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_cognitive_account.hub.identity[0].principal_id
}

resource "azurerm_role_assignment" "hub_search_index_reader" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_cognitive_account.hub.identity[0].principal_id
}

resource "azurerm_role_assignment" "hub_search_service_contributor" {
  count = var.ai_search_id != null ? 1 : 0

  scope                = var.ai_search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = azurerm_cognitive_account.hub.identity[0].principal_id
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "hub" {
  name                       = "diag-aif-${var.name}"
  target_resource_id         = azurerm_cognitive_account.hub.id
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
