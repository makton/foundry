variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "instance_number" {
  type = string
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "agw_subnet_id" {
  description = "Dedicated Application Gateway subnet ID (no delegation)"
  type        = string
}

variable "vnet_id" {
  description = "VNet resource ID — used to link the private DNS zone so all VNet resources resolve the private listener hostname"
  type        = string
}

# ── Private listener (internal domain) ───────────────────────────────────────

variable "agw_private_ip" {
  description = "Static private IP for the AGW internal frontend (must be within agw_subnet_prefix). Set to null to disable the private listener."
  type        = string
  default     = null
}

variable "agw_private_hostname" {
  description = "Internal FQDN the private listener binds to (e.g. api.foundry.internal). nginx proxies /api/ requests to this hostname."
  type        = string
  default     = "api.foundry.internal"
}

variable "agw_private_backend_key" {
  description = "Key from the backends map that the private listener routes to"
  type        = string
  default     = "chatbot-api"
}

# ── Backends (Container Apps) ─────────────────────────────────────────────────

variable "backends" {
  description = "Map of backend services. Each entry maps to one Container App or upstream FQDN."
  type = map(object({
    fqdn              = string
    # Paths routed to this backend. Leave empty to make this the default (catch-all) backend.
    path_prefixes     = optional(list(string), [])
    health_probe_path = optional(string, "/health")
    backend_port      = optional(number, 443)
    # Https recommended — Container Apps support TLS with Microsoft-issued certs
    backend_protocol  = optional(string, "Https")
  }))
}

variable "default_backend_key" {
  description = "Key from backends map used as the default (catch-all) backend"
  type        = string
}

# ── Custom Domain ─────────────────────────────────────────────────────────────

variable "custom_hostname" {
  description = "Custom domain hostname the AGW listeners bind to (e.g. chat.contoso.com). When null the listeners accept any hostname."
  type        = string
  default     = null
}

# ── SSL / TLS ─────────────────────────────────────────────────────────────────

variable "ssl_certificate_key_vault_secret_id" {
  description = "Key Vault secret ID of a PFX certificate for HTTPS. When null, HTTP-only (dev only)."
  type        = string
  default     = null
  sensitive   = true
}

variable "key_vault_id" {
  description = "Key Vault resource ID — AGW managed identity needs Get on secrets/certs"
  type        = string
  default     = null
}

# ── Scaling ───────────────────────────────────────────────────────────────────

variable "autoscale_min_capacity" {
  description = "Minimum AGW instance count (0 for dev cost savings, ≥2 for prod HA)"
  type        = number
  default     = 0
}

variable "autoscale_max_capacity" {
  description = "Maximum AGW instance count"
  type        = number
  default     = 10
}

# ── WAF ───────────────────────────────────────────────────────────────────────

variable "waf_mode" {
  description = "WAF operation mode: Detection (logs only) or Prevention (blocks)"
  type        = string
  default     = "Detection"
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "waf_owasp_version" {
  description = "OWASP rule set version"
  type        = string
  default     = "3.2"
}

# ── Rate limiting ─────────────────────────────────────────────────────────────
# Applied to the public WAF policy only (private listener uses a separate policy
# without these rules to avoid rate-limiting nginx's container IP).
#
# Rule evaluation order: chat (priority 1) fires first; a Block stops further
# evaluation so the API-broad rule (priority 2) is only reached when the chat
# quota is not yet exhausted. Set to 2000 to effectively disable a limit.

variable "waf_block_api_from_internet" {
  description = "When true, adds a WAF custom rule (priority 1) that blocks all /api/ requests reaching the public listener. Prevents direct API access from external clients — requires the SPA to be served as a same-origin BFF so browser API calls never reach the public AGW directly."
  type        = bool
  default     = false
}

variable "waf_rate_limit_chat_rpm" {
  description = "Max requests per minute per client IP for /api/chat (the streaming chat endpoint). Exceeding this returns 403."
  type        = number
  default     = 60
  validation {
    condition     = var.waf_rate_limit_chat_rpm >= 1 && var.waf_rate_limit_chat_rpm <= 2000
    error_message = "waf_rate_limit_chat_rpm must be between 1 and 2000 (Azure WAF maximum)."
  }
}

variable "waf_rate_limit_api_rpm" {
  description = "Max requests per minute per client IP for all /api/* paths. Should be >= waf_rate_limit_chat_rpm."
  type        = number
  default     = 200
  validation {
    condition     = var.waf_rate_limit_api_rpm >= 1 && var.waf_rate_limit_api_rpm <= 2000
    error_message = "waf_rate_limit_api_rpm must be between 1 and 2000 (Azure WAF maximum)."
  }
}

# ── Availability Zones ────────────────────────────────────────────────────────

variable "zones" {
  description = "Availability zones for the public IP and AGW (e.g. [\"1\", \"2\", \"3\"])"
  type        = list(string)
  default     = []
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "log_analytics_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
