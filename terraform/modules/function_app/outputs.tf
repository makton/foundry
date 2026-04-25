output "function_app_id" {
  value = azurerm_linux_function_app.main.id
}

output "function_app_name" {
  value = azurerm_linux_function_app.main.name
}

output "function_app_hostname" {
  value = azurerm_linux_function_app.main.default_hostname
}

output "managed_identity_principal_id" {
  description = "Function App managed identity principal ID — pass to CosmosDB data_contributor_principal_ids"
  value       = azurerm_user_assigned_identity.function_app.principal_id
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.function_app.client_id
}

output "service_plan_id" {
  value = azurerm_service_plan.main.id
}

output "backing_storage_name" {
  value = azurerm_storage_account.function_app.name
}

output "source_container_id" {
  description = "Resource ID of the source-documents blob container"
  value       = azurerm_storage_container.source_documents.id
}
