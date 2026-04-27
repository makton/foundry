# ── Production Environment ────────────────────────────────────────────────────
subscription_id = "00000000-0000-0000-0000-000000000000"  # Replace with your subscription ID

project_name    = "foundry"
environment     = "prod"
location        = "eastus"
location_short  = "eus"
instance_number = "001"

# ── Networking ────────────────────────────────────────────────────────────────
vnet_address_space              = ["10.1.0.0/16"]
private_endpoints_subnet_prefix = "10.1.1.0/24"
agents_subnet_prefix            = "10.1.2.0/27"
training_subnet_prefix          = "10.1.3.0/24"
container_apps_subnet_prefix    = "10.1.4.0/24"
agw_subnet_prefix               = "10.1.5.0/24"
function_app_subnet_prefix      = "10.1.6.0/26"

# ── AI Foundry ────────────────────────────────────────────────────────────────
ai_projects = {
  "chat" = {
    description  = "Production chat and RAG application"
    display_name = "Chat Application (Prod)"
  }
  "eval" = {
    description  = "Production evaluation pipeline"
    display_name = "Evaluation (Prod)"
  }
  "agents" = {
    description  = "Production AI agents"
    display_name = "Agents (Prod)"
  }
}

# ── Azure OpenAI ──────────────────────────────────────────────────────────────
openai_sku = "S0"

openai_model_deployments = {
  "gpt-4o" = {
    model_name    = "gpt-4o"
    model_version = "2024-11-20"
    scale_type    = "GlobalStandard"
    capacity      = 50     # 50 000 TPM — hard ceiling; adjust with usage data
    # Strict rate limits in prod: no bursting, callers get 429 at quota boundary
    dynamic_throttling_enabled = false
    # Only upgrade when the pinned version reaches end-of-life, not on every new default
    version_upgrade_option = "OnceCurrentVersionExpired"
  }
  "gpt-4o-mini" = {
    model_name    = "gpt-4o-mini"
    model_version = "2024-07-18"
    scale_type    = "GlobalStandard"
    capacity      = 100    # 100 000 TPM
    dynamic_throttling_enabled = false
    version_upgrade_option     = "OnceCurrentVersionExpired"
  }
  "text-embedding-3-large" = {
    model_name    = "text-embedding-3-large"
    model_version = "1"
    scale_type    = "Standard"
    capacity      = 200    # 200 000 TPM — embedding workload is high-volume
    dynamic_throttling_enabled = false
    version_upgrade_option     = "OnceCurrentVersionExpired"
  }
  "o1" = {
    model_name    = "o1"
    model_version = "2024-12-17"
    scale_type    = "GlobalStandard"
    capacity      = 20     # 20 000 TPM — o1 reasoning is expensive; keep quota tight
    dynamic_throttling_enabled = false
    # o1 version pinning is critical — reasoning model behavior changes significantly between versions
    version_upgrade_option = "NoAutoUpgrade"
  }
}

# ── AI Search ─────────────────────────────────────────────────────────────────
enable_ai_search          = true
ai_search_sku             = "standard"
ai_search_replica_count   = 2
ai_search_partition_count = 1

# ── Storage ───────────────────────────────────────────────────────────────────
storage_account_tier     = "Standard"
storage_replication_type = "ZRS"

# ── Key Vault ─────────────────────────────────────────────────────────────────
key_vault_sku = "premium"

# ── Monitoring ────────────────────────────────────────────────────────────────
log_analytics_retention_days = 90
log_analytics_sku            = "PerGB2018"

# ── Container Registry ────────────────────────────────────────────────────────
enable_container_registry = true
container_registry_sku    = "Premium"

# ── CosmosDB ──────────────────────────────────────────────────────────────────
cosmosdb_serverless             = false
cosmosdb_consistency_level      = "Session"
cosmosdb_database_name          = "foundry"
cosmosdb_total_throughput_limit = 10000   # 10k RU/s cap across all containers
cosmosdb_backup_type            = "Continuous"

cosmosdb_containers = {
  "source-documents" = {
    partition_key_path  = "/source"
    default_ttl_seconds = -1
    throughput          = 4000   # Dedicated RU/s for high-traffic container
    indexing_policy = {
      indexing_mode  = "consistent"
      included_paths = ["/*"]
      excluded_paths = ["/content/?", "/embedding/?"]  # Don't index large text/vector fields
    }
  }
  "document-chunks" = {
    partition_key_path  = "/document_id"
    default_ttl_seconds = -1
    throughput          = 4000
    indexing_policy = {
      indexing_mode  = "consistent"
      included_paths = ["/*"]
      excluded_paths = ["/embedding/?"]  # Vector field excluded from index
    }
  }
  "processing-status" = {
    partition_key_path  = "/status"
    default_ttl_seconds = 604800
  }
  "source-urls" = {
    partition_key_path  = "/id"
    default_ttl_seconds = -1       # URLs persist indefinitely
    throughput          = 400      # Dedicated RU/s — low traffic, just URL state
    indexing_policy = {
      indexing_mode  = "consistent"
      included_paths = ["/*"]
      excluded_paths = []
    }
  }
}

# ── Function App ──────────────────────────────────────────────────────────────
function_app_service_plan_sku   = "EP2"
function_app_python_version     = "3.11"
function_app_zone_balancing     = true
openai_embedding_deployment     = "text-embedding-3-large"
source_storage_container_name   = "source-documents"
ai_search_index_name            = "foundry-chunks"

# ── Application Gateway ───────────────────────────────────────────────────────
enable_app_gateway   = true
agw_waf_mode         = "Prevention"  # Block attacks in prod
agw_autoscale_min    = 2             # Minimum 2 for HA
agw_autoscale_max    = 10
agw_zones            = ["1", "2", "3"]

# WAF rule 1 — hard block: all /api/ calls from the public internet are rejected.
# nginx in chatbot-ui proxies browser API calls internally (private AGW listener),
# so this does not affect the SPA. Direct curl/tool access to /api/ is denied.
waf_block_api_from_internet = true

# Per-IP rate limiting at the WAF (public listener only).
# Rule 10 — /api/chat: 30 req/min covers ~1 message every 2 seconds; a legitimate
#   power user sending rapid short queries stays under this. A flood at 1 req/s hits
#   it in 30 seconds and is blocked for the remainder of that minute window.
# Rule 20 — /api/*: 100 req/min catches any other API endpoint abuse that slips past
#   rule 10 (e.g. URL management endpoints). Evaluated only when rule 10 passes.
waf_rate_limit_chat_rpm = 30
waf_rate_limit_api_rpm  = 100

# TLS termination — PFX must be uploaded to Key Vault as a secret before apply.
# Replace the secret ID with the versioned URL from: az keyvault secret show --vault-name kv-foundry-prod-eus-001 --name agw-tls
agw_ssl_certificate_key_vault_secret_id = "https://kv-foundry-prod-eus-001.vault.azure.net/secrets/agw-tls/abc123"

# Custom domain — create a CNAME from this hostname to the AGW public IP before apply.
agw_custom_hostname = "chat.contoso.com"

# Private listener: AGW gets a second frontend IP (internal, within agw_subnet_prefix).
# nginx in chatbot-ui proxies /api/ to http://api.foundry.internal (private DNS → this IP).
# chatbot-api is no longer routed from the public listener — only via the private path.
agw_private_ip       = "10.1.5.10"
agw_private_hostname = "api.foundry.internal"

agw_backends = {
  "chatbot-api" = {
    # No public path prefixes — chatbot-api is only reachable via the private listener.
    # The backend pool still exists so the private routing rule can reference it.
    path_prefixes     = []
    health_probe_path = "/health"
    backend_port      = 443
    backend_protocol  = "Https"
  }
  "chatbot-ui" = {
    path_prefixes     = []                  # Default backend — serves the React SPA + proxies /api/
    health_probe_path = "/health"
    backend_port      = 443
    backend_protocol  = "Https"
  }
}
agw_default_backend_key = "chatbot-ui"

# ── Container Apps ────────────────────────────────────────────────────────────
container_apps_internal_load_balancer = true   # Private — fronted by App Gateway or APIM
container_apps_zone_redundancy        = true

# Images are auto-derived from the ACR login server at plan time.
# Pin to specific digests for immutable prod deployments:
# chatbot_ui_image  = "acrfoundryprod001.azurecr.io/chatbot-ui@sha256:abc123..."
# chatbot_api_image = "acrfoundryprod001.azurecr.io/chatbot-api@sha256:abc123..."
chatbot_ui_image_tag  = "latest"
chatbot_api_image_tag = "latest"

api_apps = {
  "chatbot-ui" = {
    image                     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    target_port               = 8080
    external_ingress          = true
    min_replicas              = 2
    max_replicas              = 10
    cpu                       = 0.5
    memory                    = "1Gi"
    scale_concurrent_requests = 200
    custom_env_vars           = {}
    # nginx + MSAL SPA — receives auth env vars for runtime config injection
    needs_openai       = false
    needs_ai_search    = false
    needs_key_vault    = false
    needs_storage_read = false
    needs_auth         = true
  }
  "chatbot-api" = {
    image                     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    target_port               = 8080
    external_ingress          = true
    min_replicas              = 2
    max_replicas              = 20
    cpu                       = 1.0
    memory                    = "2Gi"
    scale_concurrent_requests = 100
    custom_env_vars = {
      AZURE_OPENAI_CHAT_DEPLOYMENT = "gpt-4o"
      CHATBOT_SYSTEM_PROMPT        = "You are a helpful AI assistant for the Azure AI Foundry platform. Be concise, accurate, and cite your sources when referencing documents."
    }
    needs_openai        = true
    needs_ai_search     = true
    needs_key_vault     = true
    needs_storage_read  = false
    needs_cosmosdb_read = true
    needs_auth          = true
  }
}

# ── Authentication ────────────────────────────────────────────────────────────
# Redirect URIs registered on the SPA app registration in Entra ID.
# Must match the exact origin users access the app from (no trailing slash for origin).
auth_ui_redirect_uris = [
  "https://chat.contoso.com",
]

# ── RBAC ──────────────────────────────────────────────────────────────────────
ai_hub_owners       = []  # Add object IDs: ["00000000-0000-0000-0000-000000000000"]
ai_hub_contributors = []
ai_hub_readers      = []

# ── Budget ────────────────────────────────────────────────────────────────────
enable_budget_alert = true
budget_amount       = 2000                       # $2 000/month — covers prod AI workloads
budget_start_date   = "2026-01-01T00:00:00Z"    # First day of the current year
budget_alert_emails = [
  "platform-team@contoso.com",
  "finops@contoso.com",
]

# ── Tags ──────────────────────────────────────────────────────────────────────
tags = {
  cost_center  = "engineering"
  team         = "platform"
  criticality  = "high"
  data_class   = "confidential"
}
