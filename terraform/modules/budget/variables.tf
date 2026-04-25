variable "name" {
  type = string
}

variable "instance_number" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  description = "Resource group ID — budget is scoped to this group's spend"
  type        = string
}

# ── Budget ────────────────────────────────────────────────────────────────────

variable "amount" {
  description = "Monthly budget ceiling in the subscription's billing currency (e.g. 500 = $500 USD)"
  type        = number

  validation {
    condition     = var.amount > 0
    error_message = "amount must be a positive number."
  }
}

variable "start_date" {
  description = "First day of the budget monitoring period in RFC3339 format. Must be the first of a month (e.g. 2026-01-01T00:00:00Z). The budget recurs monthly from this date."
  type        = string

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.start_date))
    error_message = "start_date must be the first day of a month in RFC3339 format: YYYY-MM-01T00:00:00Z."
  }
}

# ── Notifications ─────────────────────────────────────────────────────────────

variable "alert_emails" {
  description = "List of email addresses that receive budget alert notifications"
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "At least one alert email address is required."
  }

  validation {
    condition     = alltrue([for addr in var.alert_emails : can(regex("^[^@]+@[^@]+\\.[^@]+$", addr))])
    error_message = "All entries in alert_emails must be valid email addresses."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
