# ── CosmosDB Account ──────────────────────────────────────────────────────────

resource "azurerm_cosmosdb_account" "main" {
  name                = "cosmos-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"  # NoSQL / Core API

  consistency_policy {
    consistency_level = var.consistency_level
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  # Serverless capacity — no RU provisioning, pay-per-request (ideal for dev/variable load)
  dynamic "capabilities" {
    for_each = var.serverless ? [1] : []
    content {
      name = "EnableServerless"
    }
  }

  # Cap total throughput so a misconfigured container can't run up the bill
  dynamic "capacity" {
    for_each = !var.serverless && var.total_throughput_limit != null ? [1] : []
    content {
      total_throughput_limit = var.total_throughput_limit
    }
  }

  # All access through private endpoint — no public or virtual network access
  public_network_access_enabled         = false
  is_virtual_network_filter_enabled     = false
  network_acl_bypass_for_azure_services = false

  backup {
    type = var.backup_type
    # Continuous backup enables point-in-time restore
    dynamic "continuous_mode_properties" {
      for_each = var.backup_type == "Continuous" ? [1] : []
      content {
        tier = var.continuous_backup_tier
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# ── SQL Database ──────────────────────────────────────────────────────────────

resource "azurerm_cosmosdb_sql_database" "main" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name

  # Shared throughput across all containers (omit when serverless or per-container throughput)
  dynamic "autoscale_settings" {
    for_each = !var.serverless && var.database_throughput != null ? [1] : []
    content {
      max_throughput = var.database_throughput
    }
  }
}

# ── Containers ────────────────────────────────────────────────────────────────

resource "azurerm_cosmosdb_sql_container" "containers" {
  for_each = var.containers

  name                = each.key
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  database_name       = azurerm_cosmosdb_sql_database.main.name
  partition_key_path  = each.value.partition_key_path
  partition_key_version = 2

  default_ttl            = each.value.default_ttl_seconds
  analytical_storage_ttl = each.value.analytical_storage_ttl

  # Per-container autoscale throughput (overrides database-level shared throughput)
  dynamic "autoscale_settings" {
    for_each = !var.serverless && each.value.throughput != null ? [1] : []
    content {
      max_throughput = each.value.throughput
    }
  }

  dynamic "unique_key" {
    for_each = each.value.unique_key_paths
    content {
      paths = [unique_key.value]
    }
  }

  indexing_policy {
    indexing_mode = each.value.indexing_policy.indexing_mode

    dynamic "included_path" {
      for_each = each.value.indexing_policy.included_paths
      content {
        path = included_path.value
      }
    }

    dynamic "excluded_path" {
      for_each = each.value.indexing_policy.excluded_paths
      content {
        path = excluded_path.value
      }
    }
  }
}

# ── Private Endpoint ──────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "cosmosdb" {
  name                = "pe-cosmos-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-cosmos-${var.name}"
    private_connection_resource_id = azurerm_cosmosdb_account.main.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-cosmos-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_cosmosdb]
  }
}

# ── Data Plane RBAC ───────────────────────────────────────────────────────────
# CosmosDB uses its own built-in role system (not Azure RBAC) for data access.
# Built-in role IDs:
#   00000000-0000-0000-0000-000000000002 = Cosmos DB Built-in Data Contributor
#   00000000-0000-0000-0000-000000000001 = Cosmos DB Built-in Data Reader

resource "azurerm_cosmosdb_sql_role_assignment" "data_contributors" {
  for_each = toset(var.data_contributor_principal_ids)

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = each.value
  scope               = azurerm_cosmosdb_account.main.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "data_readers" {
  for_each = toset(var.data_reader_principal_ids)

  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.main.name
  role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000001"
  principal_id        = each.value
  scope               = azurerm_cosmosdb_account.main.id
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "cosmosdb" {
  name                       = "diag-cosmos-${var.name}"
  target_resource_id         = azurerm_cosmosdb_account.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "DataPlaneRequests"
  }
  enabled_log {
    category = "QueryRuntimeStatistics"
  }
  enabled_log {
    category = "PartitionKeyStatistics"
  }
  enabled_log {
    category = "ControlPlaneRequests"
  }

  metric {
    category = "Requests"
  }
}
