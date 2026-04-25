output "storage_account_id" {
  value = azurerm_storage_account.main.id
}

output "storage_account_name" {
  value = azurerm_storage_account.main.name
}

output "storage_account_primary_blob_endpoint" {
  value = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_dfs_endpoint" {
  value = azurerm_storage_account.main.primary_dfs_endpoint
}
