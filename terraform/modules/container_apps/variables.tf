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

variable "container_apps_subnet_id" {
  description = "Subnet ID for the Container Apps Environment (delegated to Microsoft.App/environments)"
  type        = string
}

variable "vnet_id" {
  description = "Virtual network ID for private DNS zone VNet link"
  type        = string
}

# ── AI Service Connections ────────────────────────────────────────────────────

variable "openai_id" {
  description = "Azure OpenAI resource ID (for RBAC)"
  type        = string
}

variable "openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  type        = string
}

variable "ai_search_id" {
  description = "Azure AI Search resource ID (optional)"
  type        = string
  default     = null
}

variable "ai_search_endpoint" {
  description = "Azure AI Search endpoint URL (optional)"
  type        = string
  default     = null
}

variable "key_vault_id" {
  description = "Key Vault resource ID (for RBAC)"
  type        = string
}

variable "key_vault_uri" {
  description = "Key Vault URI"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account resource ID (for RBAC)"
  type        = string
}

variable "cosmosdb_endpoint" {
  description = "CosmosDB account endpoint URL (injected into apps that declare needs_cosmosdb_read)"
  type        = string
  default     = null
}

variable "cosmosdb_database_name" {
  description = "CosmosDB database name (injected into apps that declare needs_cosmosdb_read)"
  type        = string
  default     = null
}

variable "container_registry_id" {
  description = "Container Registry resource ID (for AcrPull RBAC, optional)"
  type        = string
  default     = null
}

variable "container_registry_login_server" {
  description = "Container Registry login server URL"
  type        = string
  default     = null
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "log_analytics_id" {
  description = "Log Analytics workspace resource ID"
  type        = string
}

variable "application_insights_connection_string" {
  description = "Application Insights connection string for the API apps"
  type        = string
  sensitive   = true
}

# ── Environment Configuration ─────────────────────────────────────────────────

variable "zone_redundancy_enabled" {
  description = "Enable zone redundancy for the Container Apps Environment (requires Premium subnet)"
  type        = bool
  default     = false
}

variable "internal_load_balancer_enabled" {
  description = "Use internal load balancer (VNet-only access). Set false only for public-facing dev environments."
  type        = bool
  default     = true
}

# ── API Apps ──────────────────────────────────────────────────────────────────

variable "api_apps" {
  description = "Map of Container Apps to deploy as API endpoints"
  type = map(object({
    image                     = string
    target_port               = optional(number, 8080)
    external_ingress          = optional(bool, true)
    min_replicas              = optional(number, 1)
    max_replicas              = optional(number, 10)
    cpu                       = optional(number, 0.5)
    memory                    = optional(string, "1Gi")
    revision_mode             = optional(string, "Single")
    scale_concurrent_requests = optional(number, 100)
    custom_env_vars           = optional(map(string), {})
    secrets = optional(map(object({
      key_vault_secret_id = string
    })), {})
    # Role flags — each app gets its own identity with only the roles it declares
    needs_openai        = optional(bool, false)
    needs_ai_search     = optional(bool, false)
    needs_key_vault     = optional(bool, false)
    needs_storage_read  = optional(bool, false)
    needs_cosmosdb_read = optional(bool, false)
    # Auth flag — injects Entra ID config for JWT validation (api) or MSAL (ui)
    needs_auth          = optional(bool, false)
  }))
  default = {
    "chatbot-ui" = {
      image            = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      target_port      = 8080
      external_ingress = true
      min_replicas     = 1
      max_replicas     = 5
    }
    "chatbot-api" = {
      image             = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      target_port       = 8080
      external_ingress  = true
      min_replicas      = 1
      max_replicas      = 5
      needs_openai      = true
      needs_ai_search   = true
      needs_key_vault   = true
    }
  }
}

# ── Authentication ────────────────────────────────────────────────────────────
# Injected into apps that declare needs_auth = true.
# chatbot-api uses AZURE_TENANT_ID + AZURE_API_CLIENT_ID to validate JWT Bearer tokens.
# chatbot-ui uses all four to generate the runtime MSAL config (env-config.js).

variable "azure_tenant_id" {
  description = "Entra ID tenant ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_api_client_id" {
  description = "chatbot-api application (client) ID — used as the expected JWT audience"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_ui_client_id" {
  description = "chatbot-ui SPA application (client) ID — used by MSAL in the browser"
  type        = string
  default     = ""
}

variable "azure_api_scope" {
  description = "Full OAuth2 scope string the SPA requests (api://<client_id>/Chat.Read)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
