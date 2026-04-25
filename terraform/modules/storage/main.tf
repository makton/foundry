locals {
  # Storage account name: no hyphens, max 24 chars, alphanumeric only
  storage_name_raw = replace("st${var.name}${var.instance_number}", "-", "")
  storage_name     = substr(local.storage_name_raw, 0, 24)

  # Private endpoint configs for each storage sub-resource
  storage_pe_configs = {
    blob  = { subresource = "blob", dns_key = "blob" }
    file  = { subresource = "file", dns_key = "file" }
    queue = { subresource = "queue", dns_key = "queue" }
    table = { subresource = "table", dns_key = "table" }
    dfs   = { subresource = "dfs", dns_key = "dfs" }
  }
}

resource "azurerm_storage_account" "main" {
  name                = local.storage_name
  location            = var.location
  resource_group_name = var.resource_group_name

  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  is_hns_enabled            = true   # Hierarchical namespace for Data Lake Gen2
  https_traffic_only_enabled = true
  min_tls_version           = "TLS1_2"

  # Disable public access — all access via private endpoints
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled            = true
    change_feed_enabled           = true
    last_access_time_enabled      = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  tags = var.tags
}

# ── Private Endpoints (one per sub-resource) ──────────────────────────────────

resource "azurerm_private_endpoint" "storage" {
  for_each = local.storage_pe_configs

  name                = "pe-st-${each.key}-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-st-${each.key}-${var.name}"
    private_connection_resource_id = azurerm_storage_account.main.id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-st-${each.key}-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.value.dns_key]]
  }
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-st-blob-${var.name}"
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
  metric {
    category = "Capacity"
  }
  metric {
    category = "Transaction"
  }
}
