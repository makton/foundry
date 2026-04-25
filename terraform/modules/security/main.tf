data "azurerm_client_config" "current" {}

# ── User-Assigned Managed Identity ────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "main" {
  name                = "id-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

resource "azurerm_key_vault" "main" {
  name                = "kv-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = var.key_vault_sku

  # Required for AI Hub managed network: soft delete + purge protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Deny public access — all traffic via private endpoint
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  tags = var.tags
}

# ── Key Vault RBAC — platform identity ────────────────────────────────────────

resource "azurerm_role_assignment" "kv_managed_identity_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_role_assignment" "kv_managed_identity_crypto_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

resource "azurerm_role_assignment" "kv_managed_identity_certs_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}

# Grant the deploying principal admin access so it can manage secrets during provisioning
resource "azurerm_role_assignment" "kv_deployer_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ── Private Endpoint ──────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${var.name}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdns-kv-${var.name}"
    private_dns_zone_ids = [var.private_dns_zone_key_vault]
  }
}

# ── Diagnostic Settings ───────────────────────────────────────────────────────

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-${var.name}"
  target_resource_id         = azurerm_key_vault.main.id
  log_analytics_workspace_id = var.log_analytics_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  metric {
    category = "AllMetrics"
  }
}
