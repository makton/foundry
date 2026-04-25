output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "log_analytics_workspace_guid" {
  description = "Log Analytics workspace GUID — required by NSG Traffic Analytics"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "log_analytics_workspace_location" {
  description = "Log Analytics workspace region — required by NSG Traffic Analytics"
  value       = azurerm_log_analytics_workspace.main.location
}

output "application_insights_id" {
  value = azurerm_application_insights.main.id
}

output "application_insights_instrumentation_key" {
  value     = azurerm_application_insights.main.instrumentation_key
  sensitive = true
}

output "application_insights_connection_string" {
  value     = azurerm_application_insights.main.connection_string
  sensitive = true
}
