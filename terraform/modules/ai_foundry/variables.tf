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

variable "ai_projects" {
  description = "Map of AI projects to create. Each project gets three Entra security groups (admins/developers/readers) with RBAC scoped to that project."
  type = map(object({
    description       = optional(string, "")
    display_name      = optional(string, "")
    admin_members     = optional(list(string), [])  # Entra object IDs → Azure AI Administrator on this project
    developer_members = optional(list(string), [])  # Entra object IDs → Azure AI Developer on this project
    reader_members    = optional(list(string), [])  # Entra object IDs → Reader on this project
  }))
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "agents_subnet_id" {
  description = "Agents subnet ID for AI Foundry VNet injection"
  type        = string
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

variable "cmk_key_versionless_id" {
  description = "Versionless Key Vault key ID for CMK on the AI Foundry hub."
  type        = string
}

variable "cmk_key_id" {
  description = "ARM resource ID of the CMK key, used to scope the RBAC grant."
  type        = string
}

variable "log_analytics_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
