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

# ── Service Plan ──────────────────────────────────────────────────────────────

variable "service_plan_sku" {
  description = "App Service Plan SKU. Use EP1/EP2/EP3 for Premium (required for VNet integration). FC1 for Flex Consumption."
  type        = string
  default     = "EP1"
}

variable "zone_balancing_enabled" {
  description = "Spread function instances across availability zones (Premium plan only)"
  type        = bool
  default     = false
}

# ── Runtime ───────────────────────────────────────────────────────────────────

variable "python_version" {
  description = "Python runtime version for the Function App"
  type        = string
  default     = "3.11"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "function_app_subnet_id" {
  description = "Subnet ID for outbound VNet integration (delegated to Microsoft.Web/serverFarms)"
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the Function App inbound private endpoint"
  type        = string
}

variable "private_dns_zone_function_app" {
  description = "Resource ID of the privatelink.azurewebsites.net DNS zone"
  type        = string
}

# ── Backing Storage ───────────────────────────────────────────────────────────
# Separate storage account used internally by the Functions host (locks, checkpoints).
# Access is scoped to the Function App subnet via service endpoint and network rules.

variable "function_app_subnet_address_prefix" {
  description = "CIDR of the function_app subnet — used for storage network rule"
  type        = string
}

# ── AI service connections ────────────────────────────────────────────────────

variable "cosmosdb_endpoint" {
  description = "CosmosDB account endpoint URL"
  type        = string
}

variable "cosmosdb_database_name" {
  description = "Name of the CosmosDB database"
  type        = string
}

variable "cosmosdb_documents_container" {
  description = "Name of the source-documents CosmosDB container"
  type        = string
}

variable "cosmosdb_chunks_container" {
  description = "Name of the document-chunks CosmosDB container"
  type        = string
}

variable "cosmosdb_status_container" {
  description = "Name of the processing-status CosmosDB container"
  type        = string
}

variable "cosmosdb_urls_container" {
  description = "Name of the source-urls CosmosDB container (tracks URLs queued for ingestion)"
  type        = string
  default     = "source-urls"
}

variable "openai_endpoint" {
  description = "Azure OpenAI endpoint URL (for generating embeddings)"
  type        = string
}

variable "openai_embedding_deployment" {
  description = "Azure OpenAI embedding model deployment name"
  type        = string
  default     = "text-embedding-3-large"
}

variable "source_storage_account_name" {
  description = "Main storage account name (where source documents are uploaded)"
  type        = string
}

variable "source_storage_container_name" {
  description = "Blob container name to watch for new source documents"
  type        = string
  default     = "source-documents"
}

variable "ai_search_endpoint" {
  description = "Azure AI Search endpoint (optional — for pushing chunks to a search index)"
  type        = string
  default     = null
}

variable "ai_search_index_name" {
  description = "AI Search index name to push document chunks into"
  type        = string
  default     = "foundry-chunks"
}

variable "key_vault_uri" {
  description = "Key Vault URI"
  type        = string
}

# ── RBAC targets ──────────────────────────────────────────────────────────────

variable "cosmosdb_account_id" {
  description = "CosmosDB account resource ID (for RBAC assignment)"
  type        = string
}

variable "source_storage_account_id" {
  description = "Main storage account resource ID (for RBAC — read source documents)"
  type        = string
}

variable "openai_id" {
  description = "Azure OpenAI resource ID (for RBAC — call embedding API)"
  type        = string
}

variable "ai_search_id" {
  description = "AI Search resource ID (for RBAC, optional)"
  type        = string
  default     = null
}

variable "key_vault_id" {
  description = "Key Vault resource ID (for RBAC — read secrets)"
  type        = string
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "log_analytics_id" {
  type = string
}

variable "application_insights_connection_string" {
  type      = string
  sensitive = true
}

variable "foundry_agent_endpoint" {
  description = "Full HTTPS URL of the Foundry Hosted Agent invocations endpoint (set after az foundry agent deploy)"
  type        = string
  default     = ""
}

variable "eval_jobs_queue_name" {
  description = "Name of the Storage Queue that chatbot-api enqueues evaluation jobs to"
  type        = string
  default     = "eval-jobs"
}

variable "eval_queue_storage_account_name" {
  description = "Name of the storage account containing the eval-jobs queue (the main storage account)"
  type        = string
  default     = ""
}

variable "cosmosdb_eval_container" {
  description = "Name of the CosmosDB container for chat evaluation records"
  type        = string
  default     = "chat-evaluations"
}

variable "cmk_key_versionless_id" {
  description = "Versionless Key Vault key ID for CMK on the Function App backing storage."
  type        = string
}

variable "cmk_key_id" {
  description = "ARM resource ID of the CMK key, used to scope the RBAC grant."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
