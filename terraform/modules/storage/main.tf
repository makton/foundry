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

resource "azurerm_user_assigned_identity" "cmk" {
  name                = "id-st-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk_crypto_user" {
  scope                = var.cmk_key_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cmk.principal_id
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

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cmk.id]
  }

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

resource "azurerm_storage_account_customer_managed_key" "main" {
  storage_account_id        = azurerm_storage_account.main.id
  key_vault_key_id          = var.cmk_key_versionless_id
  user_assigned_identity_id = azurerm_user_assigned_identity.cmk.id

  depends_on = [azurerm_role_assignment.cmk_crypto_user]
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
