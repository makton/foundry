output "environment_id" {
  description = "Container Apps Environment resource ID"
  value       = azurerm_container_app_environment.main.id
}

output "environment_name" {
  description = "Container Apps Environment name"
  value       = azurerm_container_app_environment.main.name
}

output "environment_default_domain" {
  description = "Default domain for the Container Apps Environment"
  value       = azurerm_container_app_environment.main.default_domain
}

output "environment_static_ip" {
  description = "Static IP address of the internal load balancer (when internal_load_balancer_enabled = true)"
  value       = azurerm_container_app_environment.main.static_ip_address
}

output "managed_identity_client_ids" {
  description = "Map of app name to managed identity client ID — each app has its own identity"
  value       = { for k, v in azurerm_user_assigned_identity.api_apps : k => v.client_id }
}

output "managed_identity_principal_ids" {
  description = "Map of app name to managed identity principal ID"
  value       = { for k, v in azurerm_user_assigned_identity.api_apps : k => v.principal_id }
}

output "api_app_ids" {
  description = "Map of API app names to resource IDs"
  value       = { for k, v in azurerm_container_app.api : k => v.id }
}

output "api_app_urls" {
  description = "Map of API app names to their ingress FQDNs"
  value       = { for k, v in azurerm_container_app.api : k => try(v.ingress[0].fqdn, null) }
}
