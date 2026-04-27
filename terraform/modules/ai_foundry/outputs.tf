output "ai_hub_id" {
  value = azurerm_cognitive_account.hub.id
}

output "ai_hub_name" {
  value = azurerm_cognitive_account.hub.name
}

output "ai_hub_principal_id" {
  value = azurerm_cognitive_account.hub.identity[0].principal_id
}

output "ai_project_ids" {
  value = { for k, v in azurerm_cognitive_account_project.projects : k => v.id }
}

output "ai_project_names" {
  value = { for k, v in azurerm_cognitive_account_project.projects : k => v.name }
}

output "ai_project_principal_ids" {
  value = { for k, v in azurerm_cognitive_account_project.projects : k => v.identity[0].principal_id }
}
