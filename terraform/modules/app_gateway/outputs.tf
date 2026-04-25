output "agw_id" {
  description = "Application Gateway resource ID"
  value       = azurerm_application_gateway.main.id
}

output "agw_name" {
  description = "Application Gateway name"
  value       = azurerm_application_gateway.main.name
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.agw.ip_address
}

output "public_ip_id" {
  description = "Public IP resource ID"
  value       = azurerm_public_ip.agw.id
}

output "waf_policy_id" {
  description = "Public WAF policy resource ID (includes rate-limit custom rules)"
  value       = azurerm_web_application_firewall_policy.main.id
}

output "private_waf_policy_id" {
  description = "Internal WAF policy resource ID (OWASP only, no rate-limit rules)"
  value       = local.private_enabled ? azurerm_web_application_firewall_policy.private[0].id : null
}

output "agw_managed_identity_principal_id" {
  description = "AGW managed identity principal ID"
  value       = azurerm_user_assigned_identity.agw.principal_id
}

output "backend_pool_names" {
  description = "Map of backend key to AGW backend pool name"
  value       = { for k in keys(var.backends) : k => "backend-${k}" }
}

output "private_ip_address" {
  description = "AGW private IP address (null when private listener is disabled)"
  value       = var.agw_private_ip
}

output "private_hostname" {
  description = "Internal FQDN of the private AGW listener (null when disabled)"
  value       = local.private_enabled ? var.agw_private_hostname : null
}
