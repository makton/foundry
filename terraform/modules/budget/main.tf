# ── Action Group ──────────────────────────────────────────────────────────────
# Central notification target for all budget alerts.
# Add email_receiver blocks for each recipient; additional channels (SMS, webhook,
# Logic App) can be added here without touching the budget resource.

resource "azurerm_monitor_action_group" "budget" {
  name                = "ag-budget-${var.name}-${var.instance_number}"
  resource_group_name = var.resource_group_name
  short_name          = "budget"
  tags                = var.tags

  dynamic "email_receiver" {
    # Keyed by index so names are stable even if the list order changes
    for_each = { for i, addr in var.alert_emails : tostring(i) => addr }
    content {
      name                    = "recipient-${email_receiver.key}"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

# ── Monthly Budget ─────────────────────────────────────────────────────────────
# Scoped to the resource group so the alert tracks only this environment's spend.
# Two thresholds fire in sequence:
#   1. 80 % Forecasted — warns before the month ends while there is still time to act
#   2. 100 % Actual    — confirms the budget has been reached

resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${var.name}-${var.instance_number}"
  resource_group_id = var.resource_group_id

  amount     = var.amount
  time_grain = "Monthly"

  time_period {
    start_date = var.start_date
    # No end_date — budget recurs monthly until explicitly deleted
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_groups = [azurerm_monitor_action_group.budget.id]
  }
}
