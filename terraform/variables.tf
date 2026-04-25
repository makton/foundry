variable "subscription_id" {
  description = "Azure subscription ID for resource deployment"
  type        = string
}

variable "use_oidc" {
  description = "Use OIDC authentication (for CI/CD pipelines)"
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Short project name used in resource naming (alphanumeric, max 8 chars)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{1,8}$", var.project_name))
    error_message = "project_name must be 1-8 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "Primary Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  description = "Short location abbreviation for naming (e.g. eus for eastus)"
  type        = string
  default     = "eus"
}

variable "instance_number" {
  description = "Instance number suffix for resources (e.g. 001)"
  type        = string
  default     = "001"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "private_endpoints_subnet_prefix" {
  description = "CIDR prefix for private endpoints subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "agents_subnet_prefix" {
  description = "CIDR prefix for AI Foundry agent subnet (delegated to Microsoft.App/environments, min /27)"
  type        = string
  default     = "10.0.2.0/27"
}

variable "training_subnet_prefix" {
  description = "CIDR prefix for ML training compute subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "container_apps_subnet_prefix" {
  description = "CIDR prefix for Container Apps Environment subnet (delegated to Microsoft.App/environments, min /27)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "agw_subnet_prefix" {
  description = "CIDR prefix for Application Gateway subnet (dedicated, min /26 — /24 recommended)"
  type        = string
  default     = "10.0.5.0/24"
}

variable "function_app_subnet_prefix" {
  description = "CIDR prefix for Function App VNet integration subnet (delegated to Microsoft.Web/serverFarms, min /26)"
  type        = string
  default     = "10.0.6.0/26"
}

# ── AI Foundry ────────────────────────────────────────────────────────────────

variable "ai_hub_managed_network_isolation" {
  description = "AI Hub managed network isolation mode (Disabled, AllowInternetOutbound, AllowOnlyApprovedOutbound)"
  type        = string
  default     = "AllowOnlyApprovedOutbound"
  validation {
    condition     = contains(["Disabled", "AllowInternetOutbound", "AllowOnlyApprovedOutbound"], var.ai_hub_managed_network_isolation)
    error_message = "isolation_mode must be Disabled, AllowInternetOutbound, or AllowOnlyApprovedOutbound."
  }
}

variable "ai_projects" {
  description = "Map of AI projects to create within the AI Hub"
  type = map(object({
    description  = optional(string, "")
    display_name = optional(string, "")
  }))
  default = {
    "default" = {
      description  = "Default AI project"
      display_name = "Default Project"
    }
  }
}

# ── Azure OpenAI ──────────────────────────────────────────────────────────────

variable "openai_sku" {
  description = "Azure OpenAI SKU"
  type        = string
  default     = "S0"
}

variable "openai_model_deployments" {
  description = "Map of Azure OpenAI model deployments. capacity = provisioned TPM in thousands (e.g. 10 = 10 000 TPM)."
  type = map(object({
    model_name    = string
    model_version = string
    scale_type    = optional(string, "Standard")
    capacity      = optional(number, 10)
    rai_policy    = optional(string, "Microsoft.Default")
    dynamic_throttling_enabled = optional(bool, false)
    version_upgrade_option     = optional(string, "OnceCurrentVersionExpired")
  }))
  default = {
    "gpt-4o" = {
      model_name    = "gpt-4o"
      model_version = "2024-11-20"
      scale_type    = "GlobalStandard"
      capacity      = 30
    }
    "gpt-4o-mini" = {
      model_name    = "gpt-4o-mini"
      model_version = "2024-07-18"
      scale_type    = "GlobalStandard"
      capacity      = 60
    }
    "text-embedding-3-large" = {
      model_name    = "text-embedding-3-large"
      model_version = "1"
      scale_type    = "Standard"
      capacity      = 120
    }
  }
}

# ── AI Search ─────────────────────────────────────────────────────────────────

variable "enable_ai_search" {
  description = "Deploy Azure AI Search service"
  type        = bool
  default     = true
}

variable "ai_search_sku" {
  description = "Azure AI Search SKU (free, basic, standard, standard2, standard3)"
  type        = string
  default     = "standard"
}

variable "ai_search_replica_count" {
  description = "Number of AI Search replicas"
  type        = number
  default     = 1
}

variable "ai_search_partition_count" {
  description = "Number of AI Search partitions"
  type        = number
  default     = 1
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_account_tier" {
  description = "Storage account performance tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_replication_type" {
  description = "Storage account replication type (LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS)"
  type        = string
  default     = "ZRS"
}

# ── Key Vault ─────────────────────────────────────────────────────────────────

variable "key_vault_sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"
}

variable "enable_customer_managed_keys" {
  description = "Enable customer-managed encryption keys via Key Vault"
  type        = bool
  default     = false
}

# ── Monitoring ────────────────────────────────────────────────────────────────

variable "log_analytics_retention_days" {
  description = "Log Analytics workspace data retention in days"
  type        = number
  default     = 90
}

variable "log_analytics_sku" {
  description = "Log Analytics workspace SKU"
  type        = string
  default     = "PerGB2018"
}

# ── Container Registry ────────────────────────────────────────────────────────

variable "enable_container_registry" {
  description = "Deploy Azure Container Registry (required for custom container workloads)"
  type        = bool
  default     = true
}

variable "container_registry_sku" {
  description = "Container Registry SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Premium"
}

# ── Authentication (Entra ID) ─────────────────────────────────────────────────

variable "auth_ui_redirect_uris" {
  description = "Allowed MSAL redirect URIs for the SPA (e.g. [\"https://chat.contoso.com\"]). Include http://localhost:5173 in dev for local development."
  type        = list(string)
  default     = []
}

# ── RBAC ──────────────────────────────────────────────────────────────────────

variable "ai_hub_owners" {
  description = "List of principal IDs to assign Azure AI Owner role on the AI Hub"
  type        = list(string)
  default     = []
}

variable "ai_hub_contributors" {
  description = "List of principal IDs to assign Azure AI Developer role on the AI Hub"
  type        = list(string)
  default     = []
}

variable "ai_hub_readers" {
  description = "List of principal IDs to assign Reader role on the AI Hub"
  type        = list(string)
  default     = []
}

# ── Application Gateway ───────────────────────────────────────────────────────

variable "enable_app_gateway" {
  description = "Deploy Application Gateway (WAF_v2) to expose Container Apps APIs externally"
  type        = bool
  default     = true
}

variable "agw_custom_hostname" {
  description = "Custom domain hostname the AGW listeners bind to (e.g. chat.contoso.com). When null the listeners accept any hostname. A CNAME from this hostname to the AGW public IP must be created in DNS separately."
  type        = string
  default     = null
}

variable "agw_waf_mode" {
  description = "WAF mode: Detection (log only) or Prevention (block)"
  type        = string
  default     = "Detection"
  validation {
    condition     = contains(["Detection", "Prevention"], var.agw_waf_mode)
    error_message = "agw_waf_mode must be Detection or Prevention."
  }
}

variable "agw_autoscale_min" {
  description = "AGW minimum instance count (0 allowed for dev; use ≥2 for prod)"
  type        = number
  default     = 0
}

variable "agw_autoscale_max" {
  description = "AGW maximum instance count"
  type        = number
  default     = 10
}

variable "agw_zones" {
  description = "Availability zones for AGW and its public IP (e.g. [\"1\",\"2\",\"3\"])"
  type        = list(string)
  default     = []
}

variable "agw_ssl_certificate_key_vault_secret_id" {
  description = "Key Vault versioned secret ID for a PFX SSL cert. Null = HTTP-only (dev only)."
  type        = string
  default     = null
  sensitive   = true
}

variable "agw_backends" {
  description = "Backend routing config for the AGW. Keys must match api_apps keys. Leave path_prefixes empty for the default backend."
  type = map(object({
    path_prefixes     = optional(list(string), [])
    health_probe_path = optional(string, "/health")
    backend_port      = optional(number, 443)
    backend_protocol  = optional(string, "Https")
  }))
  default = {
    "api" = {
      path_prefixes = []   # default backend — catches all unmatched paths
    }
  }
}

variable "agw_default_backend_key" {
  description = "Key in agw_backends that receives unmatched requests"
  type        = string
  default     = "api"
}

variable "agw_private_ip" {
  description = "Static private IP for the AGW internal frontend (must be within agw_subnet_prefix, e.g. 10.1.5.10). Set to null to disable the private listener."
  type        = string
  default     = null
}

variable "agw_private_hostname" {
  description = "Internal FQDN the AGW private listener binds to (e.g. api.foundry.internal). nginx proxies /api/ to this hostname via private DNS."
  type        = string
  default     = "api.foundry.internal"
}

variable "waf_block_api_from_internet" {
  description = "Block all /api/ requests on the public AGW listener. Enable in prod to prevent direct external API access."
  type        = bool
  default     = false
}

variable "waf_rate_limit_chat_rpm" {
  description = "Max requests per minute per client IP for /api/chat. Set to 2000 to effectively disable."
  type        = number
  default     = 60
  validation {
    condition     = var.waf_rate_limit_chat_rpm >= 1 && var.waf_rate_limit_chat_rpm <= 2000
    error_message = "waf_rate_limit_chat_rpm must be between 1 and 2000."
  }
}

variable "waf_rate_limit_api_rpm" {
  description = "Max requests per minute per client IP for all /api/* paths. Should be >= waf_rate_limit_chat_rpm."
  type        = number
  default     = 200
  validation {
    condition     = var.waf_rate_limit_api_rpm >= 1 && var.waf_rate_limit_api_rpm <= 2000
    error_message = "waf_rate_limit_api_rpm must be between 1 and 2000."
  }
}

# ── Container Apps ────────────────────────────────────────────────────────────

variable "chatbot_ui_image" {
  description = "Full image reference for the chatbot UI (Nginx/React). When null, auto-derived from the ACR login server."
  type        = string
  default     = null
}

variable "chatbot_ui_image_tag" {
  description = "Image tag for the chatbot UI when auto-constructing from the ACR login server"
  type        = string
  default     = "latest"
}

variable "chatbot_api_image" {
  description = "Full image reference for the chatbot API (Express/Node). When null, auto-derived from the ACR login server."
  type        = string
  default     = null
}

variable "chatbot_api_image_tag" {
  description = "Image tag for the chatbot API when auto-constructing from the ACR login server"
  type        = string
  default     = "latest"
}

variable "container_apps_internal_load_balancer" {
  description = "Use internal (VNet-only) load balancer for the Container Apps Environment"
  type        = bool
  default     = true
}

variable "container_apps_zone_redundancy" {
  description = "Enable zone redundancy for the Container Apps Environment"
  type        = bool
  default     = false
}

variable "api_apps" {
  description = "Map of Container App API endpoints to deploy in the environment"
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
    # Role flags — each app receives its own identity with only the roles it declares
    needs_openai        = optional(bool, false)
    needs_ai_search     = optional(bool, false)
    needs_key_vault     = optional(bool, false)
    needs_storage_read  = optional(bool, false)
    needs_cosmosdb_read = optional(bool, false)
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
      image            = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      target_port      = 8080
      external_ingress = true
      min_replicas     = 1
      max_replicas     = 5
    }
  }
}

# ── CosmosDB ──────────────────────────────────────────────────────────────────

variable "cosmosdb_serverless" {
  description = "Enable CosmosDB serverless capacity mode (no RU provisioning)"
  type        = bool
  default     = false
}

variable "cosmosdb_consistency_level" {
  description = "CosmosDB consistency level"
  type        = string
  default     = "Session"
}

variable "cosmosdb_database_name" {
  description = "Name of the CosmosDB SQL database"
  type        = string
  default     = "foundry"
}

variable "cosmosdb_total_throughput_limit" {
  description = "Total RU/s cap across all containers (null = unlimited)"
  type        = number
  default     = 4000
}

variable "cosmosdb_backup_type" {
  description = "Backup policy: Continuous or Periodic"
  type        = string
  default     = "Continuous"
}

variable "cosmosdb_containers" {
  description = "CosmosDB containers to provision for source material storage"
  type = map(object({
    partition_key_path     = string
    throughput             = optional(number, null)
    default_ttl_seconds    = optional(number, -1)
    analytical_storage_ttl = optional(number, null)  # null = Synapse Link disabled
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
      default_ttl_seconds = 604800
    }
    "source-urls" = {
      partition_key_path = "/id"
      default_ttl_seconds = -1
    }
  }
}

# ── Function App ──────────────────────────────────────────────────────────────

variable "function_app_service_plan_sku" {
  description = "Service plan SKU for the import Function App (EP1/EP2/EP3 for Premium)"
  type        = string
  default     = "EP1"
}

variable "function_app_python_version" {
  description = "Python version for the Function App runtime"
  type        = string
  default     = "3.11"
}

variable "function_app_zone_balancing" {
  description = "Spread function instances across availability zones"
  type        = bool
  default     = false
}

variable "openai_embedding_deployment" {
  description = "Azure OpenAI deployment name used by the import Function App for embeddings"
  type        = string
  default     = "text-embedding-3-large"
}

variable "source_storage_container_name" {
  description = "Blob container name the Function App watches for incoming source documents"
  type        = string
  default     = "source-documents"
}

variable "ai_search_index_name" {
  description = "AI Search index name the Function App writes chunked documents into"
  type        = string
  default     = "foundry-chunks"
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ── Budget ────────────────────────────────────────────────────────────────────

variable "enable_budget_alert" {
  description = "Deploy a monthly Cost Management budget with email alerts"
  type        = bool
  default     = false
}

variable "budget_amount" {
  description = "Monthly budget ceiling in the subscription's billing currency"
  type        = number
  default     = 500
}

variable "budget_start_date" {
  description = "First day of the budget monitoring period (RFC3339, must be the first of a month, e.g. 2026-01-01T00:00:00Z)"
  type        = string
  default     = "2026-01-01T00:00:00Z"
}

variable "budget_alert_emails" {
  description = "Email addresses that receive budget alert notifications (80% forecasted, 100% actual)"
  type        = list(string)
  default     = []
}
