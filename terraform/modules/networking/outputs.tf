output "vnet_id" {
  description = "Virtual network resource ID"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = azurerm_virtual_network.main.name
}

output "private_endpoints_subnet_id" {
  description = "Private endpoints subnet ID"
  value       = azurerm_subnet.private_endpoints.id
}

output "agents_subnet_id" {
  description = "Agents subnet ID (delegated to Microsoft.App/environments)"
  value       = azurerm_subnet.agents.id
}

output "training_subnet_id" {
  description = "Training compute subnet ID"
  value       = azurerm_subnet.training.id
}

output "container_apps_subnet_id" {
  description = "Container Apps Environment subnet ID"
  value       = azurerm_subnet.container_apps.id
}

output "agw_subnet_id" {
  description = "Application Gateway dedicated subnet ID"
  value       = azurerm_subnet.agw.id
}

output "function_app_subnet_id" {
  description = "Function App VNet integration subnet ID"
  value       = azurerm_subnet.function_app.id
}

output "private_dns_zone_ids" {
  description = "Map of private DNS zone keys to resource IDs"
  value       = { for k, v in azurerm_private_dns_zone.zones : k => v.id }
}

output "private_dns_zone_names" {
  description = "Map of private DNS zone keys to zone names"
  value       = { for k, v in azurerm_private_dns_zone.zones : k => v.name }
}
