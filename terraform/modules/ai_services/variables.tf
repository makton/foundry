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

variable "openai_sku" {
  type    = string
  default = "S0"
}

variable "openai_model_deployments" {
  description = "Map of Azure OpenAI model deployments. capacity = provisioned TPM in thousands (e.g. 10 = 10 000 TPM)."
  type = map(object({
    model_name    = string
    model_version = string
    scale_type    = optional(string, "Standard")
    # Tokens Per Minute quota in thousands (K TPM). Multiply by 1 000 for actual TPM.
    capacity      = optional(number, 10)
    rai_policy    = optional(string, "Microsoft.Default")
    # Allow short bursts above the provisioned TPM before hard-throttling.
    # Useful in dev; keep false in prod for predictable rate limits.
    dynamic_throttling_enabled = optional(bool, false)
    # Controls when Azure replaces the pinned model version.
    #   OnceNewDefaultVersionAvailable – upgrades as soon as a new default ships (Azure default, risky in prod)
    #   OnceCurrentVersionExpired      – upgrades only after the pinned version reaches end-of-life
    #   NoAutoUpgrade                  – never upgrades; deployment breaks when the version is retired
    version_upgrade_option = optional(string, "OnceCurrentVersionExpired")
  }))

  validation {
    condition = alltrue([
      for d in values(var.openai_model_deployments) :
      contains(["OnceNewDefaultVersionAvailable", "OnceCurrentVersionExpired", "NoAutoUpgrade"], d.version_upgrade_option)
    ])
    error_message = "version_upgrade_option must be OnceNewDefaultVersionAvailable, OnceCurrentVersionExpired, or NoAutoUpgrade."
  }
}

variable "enable_ai_search" {
  type    = bool
  default = true
}

variable "ai_search_sku" {
  type    = string
  default = "standard"
}

variable "ai_search_replica_count" {
  type    = number
  default = 1
}

variable "ai_search_partition_count" {
  type    = number
  default = 1
}

variable "enable_container_registry" {
  type    = bool
  default = true
}

variable "container_registry_sku" {
  type    = string
  default = "Premium"
}

variable "log_analytics_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  type = string
}

variable "private_dns_zone_ids" {
  description = "Map with keys: openai, cognitive, search, acr"
  type        = map(string)
}

variable "cmk_key_versionless_ids" {
  description = "Map of resource → versionless Key Vault key ID for CMK. Required keys: openai, search, acr."
  type        = map(string)
}

variable "cmk_key_ids" {
  description = "Map of resource → ARM resource ID of the CMK key for RBAC. Required keys: openai, search, acr."
  type        = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
