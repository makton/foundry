output "budget_id" {
  description = "Cost Management budget resource ID"
  value       = azurerm_consumption_budget_resource_group.main.id
}

output "action_group_id" {
  description = "Monitor Action Group resource ID — add other alert rules here to reuse the same notification channel"
  value       = azurerm_monitor_action_group.budget.id
}
