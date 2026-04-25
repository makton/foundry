output "openai_id" {
  value = azurerm_cognitive_account.openai.id
}

output "openai_endpoint" {
  value = azurerm_cognitive_account.openai.endpoint
}

output "openai_principal_id" {
  value = azurerm_cognitive_account.openai.identity[0].principal_id
}

output "openai_model_deployment_ids" {
  value = { for k, v in azurerm_cognitive_deployment.openai_models : k => v.id }
}

output "ai_search_id" {
  value = var.enable_ai_search ? azurerm_search_service.main[0].id : null
}

output "ai_search_endpoint" {
  value = var.enable_ai_search ? "https://${azurerm_search_service.main[0].name}.search.windows.net" : null
}

output "ai_search_principal_id" {
  value = var.enable_ai_search ? azurerm_search_service.main[0].identity[0].principal_id : null
}

output "container_registry_id" {
  value = var.enable_container_registry ? azurerm_container_registry.main[0].id : null
}

output "container_registry_login_server" {
  value = var.enable_container_registry ? azurerm_container_registry.main[0].login_server : null
}
