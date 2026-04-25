output "account_id" {
  value = azurerm_cosmosdb_account.main.id
}

output "account_name" {
  value = azurerm_cosmosdb_account.main.name
}

output "endpoint" {
  value = azurerm_cosmosdb_account.main.endpoint
}

output "database_name" {
  value = azurerm_cosmosdb_sql_database.main.name
}

output "container_names" {
  value = { for k, v in azurerm_cosmosdb_sql_container.containers : k => v.name }
}

output "principal_id" {
  description = "CosmosDB system-assigned managed identity principal ID"
  value       = azurerm_cosmosdb_account.main.identity[0].principal_id
}
