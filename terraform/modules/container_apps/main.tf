locals {
  # Pre-filtered maps used by conditional role assignments — keeps for_each expressions readable
  apps_needing_openai    = { for k, v in var.api_apps : k => v if v.needs_openai }
  apps_needing_ai_search = var.ai_search_id != null ? { for k, v in var.api_apps : k => v if v.needs_ai_search } : {}
  apps_needing_key_vault = { for k, v in var.api_apps : k => v if v.needs_key_vault }
  apps_needing_storage   = { for k, v in var.api_apps : k => v if v.needs_storage_read }
  # ACR pull is always required when a custom registry is used — every app must pull its image
  apps_needing_acr_pull  = var.container_registry_id != null ? var.api_apps : {}
}

# ── Managed Identity — one per Container App ──────────────────────────────────
# Each app gets its own identity so RBAC can be scoped to exactly what that
# workload needs. A compromised chatbot-ui (Nginx) cannot call OpenAI or Key Vault
# because it was never granted those roles.

resource "azurerm_user_assigned_identity" "api_apps" {
  for_each = var.api_apps

  name                = "id-ca-${each.key}-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ── Container Apps Environment ────────────────────────────────────────────────

resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.name}-${var.instance_number}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = var.log_analytics_id

  infrastructure_subnet_id       = var.container_apps_subnet_id
  internal_load_balancer_enabled = var.internal_load_balancer_enabled
  zone_redundancy_enabled        = var.zone_redundancy_enabled

  tags = var.tags
}

# ── Private DNS for internal environment ──────────────────────────────────────
# When internal_load_balancer_enabled = true, the environment gets a static private IP.
# Apps are reachable at *.{default_domain} — requires a wildcard A record.

resource "azurerm_private_dns_zone" "container_apps" {
  count = var.internal_load_balancer_enabled ? 1 : 0

  name                = azurerm_container_app_environment.main.default_domain
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "container_apps" {
  count = var.internal_load_balancer_enabled ? 1 : 0

  name                  = "link-cae-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.container_apps[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "container_apps_wildcard" {
  count = var.internal_load_balancer_enabled ? 1 : 0

  name                = "*"
  zone_name           = azurerm_private_dns_zone.container_apps[0].name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.main.static_ip_address]
}

# ── API Container Apps ────────────────────────────────────────────────────────

resource "azurerm_container_app" "api" {
  for_each = var.api_apps

  name                         = "ca-${each.key}-${var.name}-${var.instance_number}"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = var.resource_group_name
  revision_mode                = each.value.revision_mode

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.api_apps[each.key].id]
  }

  # ACR registry authentication via this app's own managed identity
  dynamic "registry" {
    for_each = var.container_registry_login_server != null ? [1] : []
    content {
      server   = var.container_registry_login_server
      identity = azurerm_user_assigned_identity.api_apps[each.key].id
    }
  }

  # Key Vault secret references resolved using this app's identity
  dynamic "secret" {
    for_each = each.value.secrets
    content {
      name                = secret.key
      key_vault_secret_id = secret.value.key_vault_secret_id
      identity            = azurerm_user_assigned_identity.api_apps[each.key].id
    }
  }

  template {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    container {
      name   = each.key
      image  = each.value.image
      cpu    = each.value.cpu
      memory = each.value.memory

      # Client ID of this app's own identity — used by DefaultAzureCredential
      env {
        name  = "AZURE_CLIENT_ID"
        value = azurerm_user_assigned_identity.api_apps[each.key].client_id
      }

      # AI service endpoints — only injected when the app declares it needs them,
      # so chatbot-ui (Nginx) gets none of these in its environment.
      dynamic "env" {
        for_each = each.value.needs_openai ? [1] : []
        content {
          name  = "AZURE_OPENAI_ENDPOINT"
          value = var.openai_endpoint
        }
      }
      dynamic "env" {
        for_each = each.value.needs_ai_search && var.ai_search_endpoint != null ? [1] : []
        content {
          name  = "AZURE_AI_SEARCH_ENDPOINT"
          value = var.ai_search_endpoint
        }
      }
      dynamic "env" {
        for_each = each.value.needs_key_vault ? [1] : []
        content {
          name  = "AZURE_KEY_VAULT_URI"
          value = var.key_vault_uri
        }
      }
      dynamic "env" {
        for_each = each.value.needs_cosmosdb_read && var.cosmosdb_endpoint != null ? [1] : []
        content {
          name  = "COSMOSDB_ENDPOINT"
          value = var.cosmosdb_endpoint
        }
      }
      dynamic "env" {
        for_each = each.value.needs_cosmosdb_read && var.cosmosdb_database_name != null ? [1] : []
        content {
          name  = "COSMOSDB_DATABASE_NAME"
          value = var.cosmosdb_database_name
        }
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = var.application_insights_connection_string
      }

      # ── User-defined env vars ──
      dynamic "env" {
        for_each = each.value.custom_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # ── Entra ID auth config ───────────────────────────────────────────────
      # chatbot-api: AZURE_TENANT_ID + AZURE_API_CLIENT_ID → JWT validation middleware
      # chatbot-ui:  all four → entrypoint.sh generates /env-config.js for MSAL
      dynamic "env" {
        for_each = each.value.needs_auth && var.azure_tenant_id != "" ? [1] : []
        content {
          name  = "AZURE_TENANT_ID"
          value = var.azure_tenant_id
        }
      }
      dynamic "env" {
        for_each = each.value.needs_auth && var.azure_api_client_id != "" ? [1] : []
        content {
          name  = "AZURE_API_CLIENT_ID"
          value = var.azure_api_client_id
        }
      }
      dynamic "env" {
        for_each = each.value.needs_auth && var.azure_ui_client_id != "" ? [1] : []
        content {
          name  = "AZURE_UI_CLIENT_ID"
          value = var.azure_ui_client_id
        }
      }
      dynamic "env" {
        for_each = each.value.needs_auth && var.azure_api_scope != "" ? [1] : []
        content {
          name  = "AZURE_API_SCOPE"
          value = var.azure_api_scope
        }
      }
    }

    http_scale_rule {
      name                = "http-auto-scaling"
      concurrent_requests = tostring(each.value.scale_concurrent_requests)
    }
  }

  ingress {
    external_enabled = each.value.external_ingress
    target_port      = each.value.target_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.openai_user,
    azurerm_role_assignment.search_index_reader,
    azurerm_role_assignment.kv_secrets_user,
    azurerm_role_assignment.storage_blob_reader,
    azurerm_role_assignment.acr_pull,
  ]
}

# ── RBAC: per-app identity → AI services ─────────────────────────────────────
# Each for_each targets only the apps that declared the corresponding need.

resource "azurerm_role_assignment" "openai_user" {
  for_each = local.apps_needing_openai

  scope                = var.openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.api_apps[each.key].principal_id
}

resource "azurerm_role_assignment" "search_index_reader" {
  for_each = local.apps_needing_ai_search

  scope                = var.ai_search_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.api_apps[each.key].principal_id
}

resource "azurerm_role_assignment" "kv_secrets_user" {
  for_each = local.apps_needing_key_vault

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api_apps[each.key].principal_id
}

resource "azurerm_role_assignment" "storage_blob_reader" {
  for_each = local.apps_needing_storage

  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.api_apps[each.key].principal_id
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each = local.apps_needing_acr_pull

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.api_apps[each.key].principal_id
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "cae" {
  name                       = "diag-cae-${var.name}"
  target_resource_id         = azurerm_container_app_environment.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }
  enabled_log {
    category = "ContainerAppSystemLogs"
  }
  enabled_log {
    category = "AppEnvSpringAppConsoleLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
