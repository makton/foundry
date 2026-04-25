output "tenant_id" {
  description = "Entra ID tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "api_client_id" {
  description = "chatbot-api application (client) ID — used as the JWT audience claim"
  value       = azuread_application.api.client_id
  sensitive   = true
}

output "ui_client_id" {
  description = "chatbot-ui SPA application (client) ID — used by MSAL in the browser"
  value       = azuread_application.ui.client_id
}

output "api_scope" {
  description = "Full OAuth2 scope string the SPA requests (e.g. api://<client_id>/Chat.Read)"
  value       = "api://${azuread_application.api.client_id}/Chat.Read"
}
