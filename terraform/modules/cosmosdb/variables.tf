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

# ── Account ───────────────────────────────────────────────────────────────────

variable "consistency_level" {
  description = "CosmosDB consistency level"
  type        = string
  default     = "Session"
  validation {
    condition     = contains(["BoundedStaleness", "ConsistentPrefix", "Eventual", "Session", "Strong"], var.consistency_level)
    error_message = "Invalid consistency level."
  }
}

variable "serverless" {
  description = "Enable serverless capacity mode (no provisioned RUs — cost-efficient for dev)"
  type        = bool
  default     = false
}

variable "total_throughput_limit" {
  description = "Total throughput limit in RU/s across all databases (null = unlimited)"
  type        = number
  default     = 4000
}

variable "backup_type" {
  description = "Backup policy type: Continuous (point-in-time) or Periodic"
  type        = string
  default     = "Continuous"
  validation {
    condition     = contains(["Continuous", "Periodic"], var.backup_type)
    error_message = "backup_type must be Continuous or Periodic."
  }
}

variable "continuous_backup_tier" {
  description = "Continuous backup tier: Continuous7Days or Continuous30Days"
  type        = string
  default     = "Continuous7Days"
}

# ── Database & Containers ─────────────────────────────────────────────────────

variable "database_name" {
  description = "Name of the SQL API database"
  type        = string
  default     = "foundry"
}

variable "database_throughput" {
  description = "Database-level shared RU/s (null = per-container; ignored when serverless = true)"
  type        = number
  default     = null
}

variable "containers" {
  description = "Map of CosmosDB containers to create"
  type = map(object({
    partition_key_path     = string
    throughput             = optional(number, null)   # null = shared database throughput
    default_ttl_seconds    = optional(number, -1)     # -1 = no expiry
    analytical_storage_ttl = optional(number, null)    # null = Synapse Link disabled; ≥0 enables
    unique_key_paths       = optional(list(string), [])
    indexing_policy = optional(object({
      indexing_mode  = optional(string, "consistent")
      included_paths = optional(list(string), ["/*"])
      excluded_paths = optional(list(string), [])
    }), {
      indexing_mode  = "consistent"
      included_paths = ["/*"]
      excluded_paths = []
    })
  }))
  default = {
    "source-documents" = {
      partition_key_path = "/source"
      default_ttl_seconds = -1
    }
    "document-chunks" = {
      partition_key_path = "/document_id"
      default_ttl_seconds = -1
    }
    "processing-status" = {
      partition_key_path = "/status"
      default_ttl_seconds = 604800  # 7 days — job records auto-expire
    }
  }
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_cosmosdb" {
  description = "Resource ID of the privatelink.documents.azure.com DNS zone"
  type        = string
}

variable "function_app_subnet_id" {
  description = "Function App subnet ID — added to CosmosDB virtual network rules"
  type        = string
}

# ── RBAC ──────────────────────────────────────────────────────────────────────

variable "data_contributor_principal_ids" {
  description = "Principal IDs granted Cosmos DB Built-in Data Contributor (read+write)"
  type        = list(string)
  default     = []
}

variable "data_reader_principal_ids" {
  description = "Principal IDs granted Cosmos DB Built-in Data Reader (read-only)"
  type        = list(string)
  default     = []
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "log_analytics_id" {
  type = string
}

variable "cmk_key_versionless_id" {
  description = "Versionless Key Vault key ID for customer-managed encryption."
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
