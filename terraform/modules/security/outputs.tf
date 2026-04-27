output "key_vault_id" {
  value = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "managed_identity_id" {
  value = azurerm_user_assigned_identity.main.id
}

output "managed_identity_principal_id" {
  value = azurerm_user_assigned_identity.main.principal_id
}

output "managed_identity_client_id" {
  value = azurerm_user_assigned_identity.main.client_id
}

output "cmk_key_versionless_ids" {
  description = "Map of resource → versionless key ID for CMK. Keys: storage, func-storage, cosmosdb, openai, search, acr, aif."
  value       = { for k, v in azurerm_key_vault_key.cmk : k => v.versionless_id }
}

output "cmk_key_ids" {
  description = "Map of resource → ARM resource ID of the CMK key, for per-resource RBAC assignment."
  value       = { for k in local.cmk_resources : k => "${azurerm_key_vault.main.id}/keys/cmk-${k}" }
}
