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

variable "storage_account_id" {
  description = "Storage account resource ID for AI Hub"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID for AI Hub"
  type        = string
}

variable "application_insights_id" {
  description = "Application Insights resource ID for AI Hub"
  type        = string
}

variable "container_registry_id" {
  description = "Container Registry resource ID (optional)"
  type        = string
  default     = null
}

variable "openai_id" {
  description = "Azure OpenAI resource ID"
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

variable "cosmosdb_endpoint" {
  description = "CosmosDB account endpoint URL (for hub connection)"
  type        = string
}

variable "cosmosdb_id" {
  description = "CosmosDB account resource ID (for hub connection metadata)"
  type        = string
}

variable "cosmosdb_database_name" {
  description = "CosmosDB database name exposed to AI Foundry via the hub connection"
  type        = string
}

variable "managed_network_isolation" {
  description = "AI Hub managed network isolation mode"
  type        = string
  default     = "AllowOnlyApprovedOutbound"
}

variable "ai_projects" {
  description = "Map of AI projects to create"
  type = map(object({
    description  = optional(string, "")
    display_name = optional(string, "")
  }))
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  description = "Map with keys: ml_api, ml_notebooks"
  type        = map(string)
}

variable "ai_hub_owners" {
  description = "Principal IDs for Azure AI Owner role"
  type        = list(string)
  default     = []
}

variable "ai_hub_contributors" {
  description = "Principal IDs for Azure AI Developer role"
  type        = list(string)
  default     = []
}

variable "ai_hub_readers" {
  description = "Principal IDs for Reader role"
  type        = list(string)
  default     = []
}

variable "log_analytics_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
