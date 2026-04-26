# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Foundry is an Azure AI Foundry-based enterprise chatbot platform with RAG (Retrieval-Augmented Generation), document ingestion, JWT authentication, and asynchronous chat evaluation. It targets Azure with zero public PaaS exposure — all services (OpenAI, Search, CosmosDB, Key Vault, Storage) use private endpoints only.

## Commands

### chatbot-ui (React 18 + Vite)
```bash
cd src/chatbot-ui
npm run dev       # Vite dev server
npm run build     # Production build → dist/
npm run preview   # Preview production build locally
```

### chatbot-api (Node.js + Express)
```bash
cd src/chatbot-api
npm run dev       # Run with --watch (auto-reload)
npm start         # Run production server
```

### foundry-agent (Python FastAPI)
```bash
cd src/foundry-agent
python -m uvicorn agent:app --host 0.0.0.0 --port 8080
```

### function-app (Python Azure Functions)
```bash
cd src/function_app
func start        # Requires Azure Functions Core Tools
```

### Terraform
```bash
cd terraform
terraform init -backend-config=environments/backend-dev.hcl
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

### Deployment Scripts
```bash
bash scripts/build-push-chatbot.sh         # Docker build + push for UI & API
bash scripts/deploy-foundry-agent.sh       # Build, push, and deploy ML online endpoint
# Requires env vars: FOUNDRY_WORKSPACE_NAME, RESOURCE_GROUP, ACR_LOGIN_SERVER
```

## Architecture

### src/ Services

| Service | Runtime | Role |
|---|---|---|
| `chatbot-ui` | React 18 + Vite | MSAL browser auth, chat UI, workflow selector, served via nginx in Container Apps |
| `chatbot-api` | Node.js 20 + Express | REST `/api/chat`, JWT validation, Azure OpenAI + AI Search (RAG), SSE streaming, eval queue |
| `foundry-agent` | Python 3.11 + FastAPI | AI Foundry Hosted Agent; `POST /invocations` scores chat turns (groundedness, relevance, coherence) using gpt-4o |
| `function_app` | Python 3.11 + Azure Functions | Queue trigger → runs eval → writes CosmosDB; HTTP routes for URL CRUD; timer trigger → ingests URLs every 6h; Blob trigger → chunks/embeds/indexes documents |

### Request Flow
1. Browser → MSAL login → acquires JWT (Entra ID)
2. Browser → Application Gateway WAF (public listener `chat.contoso.com`) → nginx (chatbot-ui container)
3. nginx proxies `/api/` → private AGW listener (`api.foundry.internal`) → chatbot-api
4. chatbot-api validates JWT (JWKS), calls Azure OpenAI + AI Search (hybrid RAG), streams SSE back to browser
5. After streaming, chat-api enqueues eval job to Storage Queue (fire-and-forget)
6. Function App dequeues → calls foundry-agent → writes evaluation scores to CosmosDB

### Document Ingestion Flow
Blob uploaded → Function App Blob trigger → parse (PDF/DOCX/TXT) → chunk (≈500 tokens, 50 overlap) → embed (text-embedding-3-large, 1536-dim) → index in AI Search + store in CosmosDB

### Workflow System
`chatbot-api/workflows/*.json` defines pluggable chat personas (e.g., `default.json`, `document-qa.json`, `code-assistant.json`). All client-supplied workflow names are validated against this allowlist at startup.

### Terraform Modules (13)
`networking`, `security`, `storage`, `monitoring`, `auth`, `container_apps`, `function_app`, `background_worker`, `ai_services` (OpenAI + AI Search), `ai_foundry` (Hub + Projects), `app_gateway`, `cosmosdb`, `budget`. Backend state lives in Azure Storage (no local state). Per-environment configs in `environments/`.

### Network Layout
- VNet with 6 subnets: AGW (`10.x.5.0/24`), Container Apps (`10.x.4.0/24`), Function App (`10.x.6.0/26`), Agents (`10.x.2.0/27`), Private Endpoints (`10.x.1.0/24`), Training (`10.x.3.0/24`)
- All PaaS reachable only via private endpoints; `public_network_access_enabled = false` everywhere

## Key Design Decisions

- **Managed identity everywhere:** `DefaultAzureCredential` (IMDS) used throughout Python and Node services — no keys or service principals in code.
- **SSE streaming:** chatbot-api streams tokens to the client; nginx is configured with `proxy_buffering off`.
- **Fire-and-forget eval:** Evaluation never blocks the chat response; jobs are enqueued after streaming completes.
- **Image promotion:** Dev→prod uses `az acr import` with digest pinning (identical byte artifact in both ACRs).
- **Foundry Agent public reach:** The ML online endpoint (foundry-agent) does not support VNet; Function App reaches it over `AzureCloud` service tag via an NSG allowance.
- **CosmosDB partitioning:** `chat-evaluations` partitioned by `/session_id`, 90-day TTL, continuous backup in prod.

## CI/CD (Azure DevOps)

- `pipelines/chatbot.yml` — PR: validate build only; main: build+push to dev ACR, manual approval gates prod promotion
- `pipelines/terraform.yml` — PR: fmt/validate; main: plan_dev → auto apply_dev → plan_prod → manual apply_prod
