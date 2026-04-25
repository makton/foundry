resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${var.name}-${var.instance_number}"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}
