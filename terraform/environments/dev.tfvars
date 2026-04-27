# ── Dev Environment ───────────────────────────────────────────────────────────
subscription_id = "00000000-0000-0000-0000-000000000000"  # Replace with your subscription ID

project_name    = "foundry"
environment     = "dev"
location        = "eastus"
location_short  = "eus"
instance_number = "001"

# ── Networking ────────────────────────────────────────────────────────────────
vnet_address_space              = ["10.0.0.0/16"]
private_endpoints_subnet_prefix = "10.0.1.0/24"
agents_subnet_prefix            = "10.0.2.0/27"
training_subnet_prefix          = "10.0.3.0/24"
container_apps_subnet_prefix    = "10.0.4.0/24"
agw_subnet_prefix               = "10.0.5.0/24"
function_app_subnet_prefix      = "10.0.6.0/26"

# ── AI Foundry ────────────────────────────────────────────────────────────────
ai_projects = {
  "chat" = {
    description       = "Chat and RAG application project"
    display_name      = "Chat Application"
    admin_members     = []  # Entra object IDs for Azure AI Administrator on this project
    developer_members = []  # Entra object IDs for Azure AI Developer on this project
    reader_members    = []  # Entra object IDs for Reader on this project
  }
  "eval" = {
    description       = "Model evaluation and experimentation"
    display_name      = "Evaluation"
    admin_members     = []
    developer_members = []
    reader_members    = []
  }
}

# ── Azure OpenAI ──────────────────────────────────────────────────────────────
openai_sku = "S0"

openai_model_deployments = {
  "gpt-4o" = {
    model_name    = "gpt-4o"
    model_version = "2024-11-20"
    scale_type    = "GlobalStandard"
    capacity      = 10    # 10 000 TPM
    # Allow bursting in dev so low quota doesn't block iterative testing
    dynamic_throttling_enabled = true
    # Track the latest default version in dev to catch compatibility issues early
    version_upgrade_option = "OnceNewDefaultVersionAvailable"
  }
  "gpt-4o-mini" = {
    model_name    = "gpt-4o-mini"
    model_version = "2024-07-18"
    scale_type    = "GlobalStandard"
    capacity      = 20    # 20 000 TPM
    dynamic_throttling_enabled = true
    version_upgrade_option     = "OnceNewDefaultVersionAvailable"
  }
  "text-embedding-3-large" = {
    model_name    = "text-embedding-3-large"
    model_version = "1"
    scale_type    = "Standard"
    capacity      = 30    # 30 000 TPM
    dynamic_throttling_enabled = true
    version_upgrade_option     = "OnceNewDefaultVersionAvailable"
  }
}

# ── AI Search ─────────────────────────────────────────────────────────────────
enable_ai_search          = true
ai_search_sku             = "basic"
ai_search_replica_count   = 1
ai_search_partition_count = 1

# ── Storage ───────────────────────────────────────────────────────────────────
storage_account_tier     = "Standard"
storage_replication_type = "LRS"

# ── Key Vault ─────────────────────────────────────────────────────────────────
key_vault_sku = "standard"

# ── Monitoring ────────────────────────────────────────────────────────────────
log_analytics_retention_days = 30
log_analytics_sku            = "PerGB2018"

# ── Container Registry ────────────────────────────────────────────────────────
enable_container_registry = true
container_registry_sku    = "Standard"

# ── CosmosDB ──────────────────────────────────────────────────────────────────
cosmosdb_serverless             = true    # Serverless = no RU provisioning, pay-per-request (ideal for dev)
cosmosdb_consistency_level      = "Session"
cosmosdb_database_name          = "foundry"
cosmosdb_total_throughput_limit = null    # N/A in serverless mode
cosmosdb_backup_type            = "Periodic"

cosmosdb_containers = {
  "source-documents" = {
    partition_key_path  = "/source"
    default_ttl_seconds = -1
  }
  "document-chunks" = {
    partition_key_path  = "/document_id"
    default_ttl_seconds = -1
  }
  "processing-status" = {
    partition_key_path  = "/status"
    default_ttl_seconds = 604800   # 7 days
  }
  "source-urls" = {
    partition_key_path  = "/id"
    default_ttl_seconds = -1       # URLs persist indefinitely
  }
  "chat-evaluations" = {
    partition_key_path  = "/session_id"
    default_ttl_seconds = 7776000  # 90 days
  }
}

# ── Function App ──────────────────────────────────────────────────────────────
function_app_service_plan_sku   = "EP1"
function_app_python_version     = "3.11"
function_app_zone_balancing     = false
openai_embedding_deployment     = "text-embedding-3-large"
source_storage_container_name   = "source-documents"
ai_search_index_name            = "foundry-chunks"

# ── Application Gateway ───────────────────────────────────────────────────────
enable_app_gateway   = true
agw_waf_mode         = "Detection"   # Detection in dev — won't block traffic
agw_autoscale_min    = 0             # Scale to zero in dev to save cost
agw_autoscale_max    = 2
agw_zones            = []            # No zone redundancy in dev

# In dev, keep /api/ reachable from the internet so developers can test endpoints
# directly with curl or Postman without going through the full SPA flow.
waf_block_api_from_internet = false

# High rate limits in dev so automated tests and manual exploration don't get blocked.
# WAF custom rules always enforce their action regardless of waf_mode (Detection vs
# Prevention), so set these high rather than relying on Detection mode to soften them.
waf_rate_limit_chat_rpm = 2000       # Azure WAF maximum — effectively disabled in dev
waf_rate_limit_api_rpm  = 2000

# No SSL cert in dev — HTTP only. Set this to a Key Vault secret ID for HTTPS.
# agw_ssl_certificate_key_vault_secret_id = null

# Custom domain — create a CNAME pointing here after the AGW public IP is known.
# Omit to accept any hostname on the public listener (default dev behaviour).
# agw_custom_hostname = "chat-dev.contoso.com"

agw_private_ip       = "10.0.5.10"
agw_private_hostname = "api.foundry.internal"

agw_backends = {
  "chatbot-api" = {
    path_prefixes     = []                  # Private listener only — not on public path
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
container_apps_internal_load_balancer = true   # Internal only — chatbot-api must not be reachable from the internet even in dev
container_apps_zone_redundancy        = false

# Images are auto-derived from the ACR login server.
# After running scripts/build-push-chatbot.sh you can pin specific digests here:
# chatbot_ui_image  = "acrfoundrydev001.azurecr.io/chatbot-ui@sha256:..."
# chatbot_api_image = "acrfoundrydev001.azurecr.io/chatbot-api@sha256:..."
chatbot_ui_image_tag  = "latest"
chatbot_api_image_tag = "latest"

api_apps = {
  "chatbot-ui" = {
    image                     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
    target_port               = 8080
    external_ingress          = true
    min_replicas              = 0   # Scale to zero in dev to save cost
    max_replicas              = 3
    cpu                       = 0.25
    memory                    = "0.5Gi"
    scale_concurrent_requests = 20
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
    min_replicas              = 0   # Scale to zero in dev to save cost
    max_replicas              = 3
    cpu                       = 0.5
    memory                    = "1Gi"
    scale_concurrent_requests = 10
    custom_env_vars = {
      AZURE_OPENAI_CHAT_DEPLOYMENT      = "gpt-4o"
      AZURE_OPENAI_EMBEDDING_DEPLOYMENT = "text-embedding-3-large"
      AZURE_AI_SEARCH_INDEX_NAME        = "foundry-chunks"
      CHATBOT_SYSTEM_PROMPT             = "You are a helpful AI assistant for the Azure AI Foundry platform. Be concise and accurate."
    }
    needs_openai        = true
    needs_ai_search     = true
    needs_key_vault     = true
    needs_storage_read  = false
    needs_cosmosdb_read = true
    needs_eval_queue    = true
    needs_auth          = true
  }
}

# ── Authentication ────────────────────────────────────────────────────────────
# Redirect URIs registered on the SPA app registration in Entra ID.
# http://localhost:5173 allows local vite dev server to complete the MSAL login flow.
auth_ui_redirect_uris = [
  "http://localhost:5173",
  # "https://chat-dev.contoso.com",   # uncomment once AGW custom hostname is set
]

# ── RBAC ──────────────────────────────────────────────────────────────────────
ai_hub_owners       = []  # Add object IDs: ["00000000-0000-0000-0000-000000000000"]
ai_hub_contributors = []
ai_hub_readers      = []

# ── Budget ────────────────────────────────────────────────────────────────────
enable_budget_alert = true
budget_amount       = 200                        # $200/month — covers dev AI workloads
budget_start_date   = "2026-01-01T00:00:00Z"    # First day of the current year
budget_alert_emails = ["platform-team@contoso.com"]

# ── Foundry Hosted Agent — Chat Accuracy Evaluator ────────────────────────────
# Set foundry_agent_endpoint after running scripts/deploy-foundry-agent.sh
# foundry_agent_endpoint = "https://<project>.services.ai.azure.com/api/projects/<id>/agents/accuracy-evaluator/endpoint/protocols/invocations"
eval_jobs_queue_name    = "eval-jobs"
cosmosdb_eval_container = "chat-evaluations"

# ── Tags ──────────────────────────────────────────────────────────────────────
tags = {
  cost_center = "engineering"
  team        = "platform"
}
