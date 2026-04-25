# Foundry Platform — Architecture

Four diagrams cover the platform:

1. [Infrastructure Overview](#1-infrastructure-overview) — all Azure resources and network topology
2. [Chatbot Request Flow](#2-chatbot-request-and-authentication-flow) — browser → AGW → nginx → API → OpenAI, with JWT auth
3. [Document Ingestion Flow](#3-document-ingestion-flow) — blob upload → Function App → AI Search + CosmosDB
4. [CI/CD Pipeline Flow](#4-cicd-pipeline-flow) — Terraform and container deployment pipelines

---

## 1. Infrastructure Overview

```mermaid
graph TD
    %% ── External ────────────────────────────────────────────────────────────────
    User(["👤 User\nBrowser"])
    ADO(["🔧 Azure DevOps\nCI/CD Pipelines"])
    EntraID(["🔑 Entra ID\nchatbot-api app reg\nchatbot-ui app reg"])

    %% ── Azure VNet ──────────────────────────────────────────────────────────────
    subgraph VNET["Azure VNet — 10.x.0.0/16"]

        subgraph AGW_SUBNET["snet-agw  10.x.5.0/24"]
            AGW["Application Gateway WAF_v2\nPublic listener — chat.contoso.com\nPrivate listener — api.foundry.internal:10.x.5.10\nOWASP + BotManager + rate-limit rules"]
        end

        subgraph CAE_SUBNET["snet-container-apps  10.x.4.0/24"]
            subgraph CAE["Container Apps Environment — internal LB only"]
                UI["chatbot-ui\nnginx 1.27 · React SPA\nMSAL browser auth\nProxies /api/ → private listener"]
                CAPI["chatbot-api\nNode.js 20 · Express\nJWT validation middleware\nSSE streaming"]
            end
        end

        subgraph FUNC_SUBNET["snet-function-app  10.x.6.0/26"]
            FUNC["Import Function App\nPython 3.11 · EP1/EP2\nBlob trigger → chunk + embed → index"]
        end

        subgraph AGENTS_SUBNET["snet-agents  10.x.2.0/27"]
            AGENTS["AI Foundry\nAgent Service"]
        end

        subgraph PE_SUBNET["snet-private-endpoints  10.x.1.0/24"]
            PE_OAI["PE → OpenAI"]
            PE_SRCH["PE → AI Search"]
            PE_COSMOS["PE → CosmosDB"]
            PE_KV["PE → Key Vault"]
            PE_ST["PE → Storage"]
            PE_ACR["PE → Container Registry"]
            PE_FUNC["PE → Function App"]
            PE_MON["PE → Monitor / Log Analytics"]
        end
    end

    %% ── PaaS Services ───────────────────────────────────────────────────────────
    subgraph PAAS["Azure PaaS — private-endpoint accessible"]
        OAI["Azure OpenAI\ngpt-4o · gpt-4o-mini\ntext-embedding-3-large\no1 (prod only)"]
        SRCH["AI Search\nbasic (dev) · standard (prod)\nIndex: foundry-chunks"]
        COSMOS["CosmosDB\nServerless (dev)\nProvisioned 10k RU/s (prod)\nContinuous backup (prod)"]
        KV["Key Vault\nstandard (dev)\npremium + CMK (prod)\nPurge protection enabled"]
        ST["Storage Account\nSource documents\nLRS (dev) · ZRS (prod)"]
        ACR["Container Registry\nStandard (dev)\nPremium (prod)"]
    end

    %% ── AI Foundry ──────────────────────────────────────────────────────────────
    subgraph FOUNDRY["AI Foundry"]
        HUB["AI Hub\naih-foundry-env-eus-001\nAllowOnlyApprovedOutbound (prod)"]
        P_CHAT["Project: chat\nChat + RAG"]
        P_EVAL["Project: eval\nEvaluation"]
        P_AGENTS["Project: agents\n(prod only)"]
        HUB --> P_CHAT
        HUB --> P_EVAL
        HUB --> P_AGENTS
    end

    %% ── Monitoring ──────────────────────────────────────────────────────────────
    subgraph MON["Monitoring"]
        LOG["Log Analytics\n30 days (dev) · 90 days (prod)\nNSG + VNet flow logs"]
        APPI["Application Insights\nSSE trace · dependency map"]
    end

    BUDGET["💰 Budget Alert\n$200/mo dev · $2 000/mo prod"]

    %% ── Traffic flows ───────────────────────────────────────────────────────────
    User        -->|HTTPS 443| AGW
    ADO         -->|az acr build / az containerapp update| ACR
    ADO         -->|terraform plan/apply| VNET

    AGW         -->|HTTPS backend pool| UI
    AGW         -.->|private listener\napi.foundry.internal| CAPI
    UI          -->|proxy /api/\n+ Authorization header| AGW

    CAPI        --> PE_OAI   --> OAI
    CAPI        --> PE_SRCH  --> SRCH
    CAPI        --> PE_COSMOS --> COSMOS
    CAPI        --> PE_KV    --> KV

    FUNC        -->|service endpoint| ST
    FUNC        --> PE_OAI
    FUNC        --> PE_SRCH
    FUNC        --> PE_COSMOS

    AGENTS      --> PE_OAI
    AGENTS      --> PE_SRCH

    ACR         --> PE_ACR
    FUNC        --> PE_FUNC

    CAPI        -.->|validate JWT\nJWKS endpoint| EntraID
    User        -.->|MSAL login| EntraID

    OAI         -.->|private DNS + PE| FOUNDRY
    SRCH        -.-> FOUNDRY
    COSMOS      -.-> FOUNDRY

    CAE         -.->|diag| LOG
    AGW         -.->|diag| LOG
    FUNC        -.->|diag| LOG
    CAPI        -.->|traces| APPI
    UI          -.->|traces| APPI
    BUDGET      -.-> LOG

    %% ── Styles ──────────────────────────────────────────────────────────────────
    classDef network   fill:#0078d4,color:#fff,stroke:#005a9e
    classDef compute   fill:#107c10,color:#fff,stroke:#054b05
    classDef paas      fill:#7a43b6,color:#fff,stroke:#5c3188
    classDef security  fill:#d83b01,color:#fff,stroke:#a32a00
    classDef monitor   fill:#ff8c00,color:#fff,stroke:#cc7000
    classDef external  fill:#505050,color:#fff,stroke:#333

    class AGW network
    class UI,CAPI,FUNC,AGENTS compute
    class OAI,SRCH,COSMOS,ST,ACR paas
    class KV,EntraID security
    class LOG,APPI,BUDGET monitor
    class User,ADO external
```

---

## 2. Chatbot Request and Authentication Flow

```mermaid
sequenceDiagram
    actor User as 👤 User

    box Browser
        participant SPA as React SPA (MSAL)
    end
    box Internet edge
        participant AGW as App Gateway WAF_v2
    end
    box VNet — Container Apps
        participant Nginx as chatbot-ui (nginx)
        participant API as chatbot-api (Express)
    end
    box Entra ID / Azure
        participant JWKS as Entra ID JWKS
        participant OAI as Azure OpenAI
    end

    %% ── First visit: silent token attempt ──────────────────────────────────────
    Note over User,SPA: First visit (unauthenticated)
    User->>SPA: Open chat.contoso.com
    SPA->>SPA: Read window.__ENV__\n(tenantId, clientId, apiScope)
    SPA->>SPA: acquireTokenSilent — no cached token
    SPA-->>User: Render login gate

    User->>SPA: Click "Sign in with Microsoft"
    SPA->>JWKS: loginPopup({ scopes: ["api://.../Chat.Read"] })
    JWKS-->>SPA: JWT access token (RS256, aud=API clientId, scp=Chat.Read)
    SPA-->>User: Render chat UI (user name shown in header)

    %% ── Chat request ────────────────────────────────────────────────────────────
    Note over User,OAI: Authenticated chat request
    User->>SPA: Type message, press Send
    SPA->>SPA: acquireTokenSilent (token from sessionStorage)
    SPA->>AGW: POST /api/chat\nAuthorization: Bearer <jwt>\nContent-Type: application/json

    Note over AGW: WAF checks:\n① BlockApiFromInternet (prod)\n② OWASP 3.2 + BotManager\n③ Rate limit /api/chat — 30 rpm/IP (prod)
    AGW->>Nginx: Forward to chatbot-ui backend pool\n(HTTPS, pick_host_name_from_backend)

    Nginx->>Nginx: Match location /api/\nresolve api.foundry.internal → 10.x.5.10
    Nginx->>AGW: Proxy to private listener\nHost: api.foundry.internal\nAuthorization: Bearer <jwt> (passed through)

    Note over AGW: Private WAF policy:\nOWASP only, no IP rate-limit\n(nginx IP, not client IP)
    AGW->>API: Route to chatbot-api backend pool

    API->>API: authenticate() middleware\nExtract Bearer token
    API->>JWKS: getSigningKey(kid) — cached 10h
    JWKS-->>API: RSA public key
    API->>API: jwt.verify(token, key,\n{ aud: API_CLIENT_ID,\n  iss: login.microsoft.../v2.0,\n  alg: RS256 })\nCheck scp contains "Chat.Read"

    API->>API: checkRateLimit(socket.remoteAddress)\n20 rpm in-process guard

    API->>OAI: chat.completions.create(stream: true)\nManaged identity token\n(DefaultAzureCredential → IMDS)

    Note over API,SPA: SSE streaming response
    loop Each token chunk
        OAI-->>API: stream chunk
        API-->>Nginx: data: {"content":"..."}\n\n
        Nginx-->>AGW: proxy_buffering off
        AGW-->>SPA: SSE chunk
        SPA-->>User: Append token to message
    end

    OAI-->>API: [stream done]
    API-->>SPA: data: [DONE]\n\n
    SPA-->>User: Message complete
```

---

## 3. Document Ingestion Flow

```mermaid
sequenceDiagram
    actor Operator as 👤 Operator / Automated Job

    box Azure Storage
        participant ST as Storage Account\n(source-documents container)
    end
    box snet-function-app
        participant FUNC as Import Function App\n(Python 3.11, EP1/EP2)
    end
    box PaaS (via private endpoints)
        participant OAI as Azure OpenAI\n(text-embedding-3-large)
        participant SRCH as AI Search\n(foundry-chunks index)
        participant COSMOS as CosmosDB\n(foundry database)
    end

    Operator->>ST: Upload source document\n(PDF, DOCX, TXT, …)
    ST-->>FUNC: Blob-created trigger

    FUNC->>COSMOS: Upsert processing-status record\nstatus=processing, ttl=7d

    Note over FUNC: Chunk document\n(sliding window, ~500 tokens + 50 overlap)

    loop Each chunk
        FUNC->>OAI: embeddings.create(text=chunk,\nmodel=text-embedding-3-large)
        OAI-->>FUNC: float[3072] embedding vector
        FUNC->>COSMOS: Upsert document-chunks record\n(chunk text + embedding)
        FUNC->>SRCH: index.upload_documents([chunk])\n(text + vector + metadata)
    end

    FUNC->>COSMOS: Upsert source-documents record\n(source URL / file ref, chunk count)
    FUNC->>COSMOS: Update processing-status\nstatus=completed

    Note over SRCH: Chatbot-api queries this index\nat /api/chat time using\nhybrid search (keyword + vector)
```

---

## 4. CI/CD Pipeline Flow

```mermaid
graph LR
    subgraph Triggers
        PR["Pull Request\nto main"]
        PUSH["Push to main"]
    end

    subgraph TF["terraform.yml — Terraform Pipeline"]
        direction TB
        TF_VAL["validate stage\nfmt check · init -backend=false · validate"]
        TF_PLAN_D["plan_dev stage\nterraform plan\n(vg-foundry-dev)"]
        TF_PLAN_P["plan_prod stage\nterraform plan\n(vg-foundry-prod)"]
        TF_APPLY_D["apply_dev stage\nDeployment job: foundry-dev env\nauto-approve on main"]
        TF_APPLY_P["apply_prod stage\nDeployment job: foundry-prod env\n⏸ manual approval required"]

        TF_VAL --> TF_PLAN_D
        TF_VAL --> TF_PLAN_P
        TF_PLAN_D --> TF_APPLY_D
        TF_PLAN_P --> TF_APPLY_P
    end

    subgraph CB["chatbot.yml — Container Pipeline"]
        direction TB
        CB_VAL["validate stage (PR only)\ndocker build --no-push\nchatbot-ui + chatbot-api"]
        CB_DEV["build_push_dev stage (main only)\naz acr build → acrfoundrydev\nchatbot-ui:BuildId + latest\nchatbot-api:BuildId + latest\naz containerapp update"]
        CB_PROD["push_prod stage\nDeployment job: foundry-prod env\n⏸ manual approval required\naz acr import dev→prod (same digest)\naz containerapp update"]

        CB_VAL --> CB_DEV
        CB_DEV --> CB_PROD
    end

    subgraph State["Terraform Remote State"]
        TS["Azure Storage\n(per-environment container)\nState file + lock"]
    end

    subgraph Registries["Azure Container Registries"]
        ACR_DEV["ACR Dev\nacrfoundrydev001"]
        ACR_PROD["ACR Prod\nacrfoundryprod001\n(AcrPull on dev ACR for import)"]
    end

    PR     --> TF_VAL
    PR     --> CB_VAL
    PUSH   --> TF_VAL
    PUSH   --> CB_VAL

    TF_PLAN_D  -.->|backend-config| TS
    TF_PLAN_P  -.->|backend-config| TS
    TF_APPLY_D -.->|backend-config| TS
    TF_APPLY_P -.->|backend-config| TS

    CB_DEV  --> ACR_DEV
    CB_PROD -->|az acr import| ACR_DEV
    CB_PROD --> ACR_PROD

    classDef stage fill:#0078d4,color:#fff,stroke:none
    classDef approval fill:#d83b01,color:#fff,stroke:none
    classDef infra fill:#7a43b6,color:#fff,stroke:none
    classDef trigger fill:#505050,color:#fff,stroke:none

    class TF_VAL,TF_PLAN_D,TF_PLAN_P,CB_VAL,CB_DEV stage
    class TF_APPLY_D infra
    class TF_APPLY_P,CB_PROD approval
    class PR,PUSH trigger
```

---

## Network Security Summary

| Subnet | NSG Inbound | NSG Outbound | Notes |
|--------|-------------|--------------|-------|
| `snet-agw` | GatewayManager (65200-65535), AzureLB, HTTPS 443, HTTP 80 from Internet | VNet only (Deny-All-Internet) | AGW subnet requires GatewayManager rule |
| `snet-container-apps` | VNet (443, 80) only; Deny-Internet-Inbound @ 4096 | — | Internal LB: no public FQDN |
| `snet-function-app` | No inbound | VNet, AzureCloud 443; Deny-All-Internet | Outbound via service endpoints |
| `snet-agents` | Deny-All-Inbound | — | AI Foundry Agent Service delegation |
| `snet-private-endpoints` | VNet only; Deny-All-Inbound | — | All PaaS traffic stays in VNet |

## Key Security Controls

| Control | Implementation |
|---------|---------------|
| **TLS everywhere** | AGW terminates public TLS; backends use HTTPS with Container Apps managed certs; `min_tls_version = TLS1_2` on all storage |
| **Zero public PaaS endpoints** | All PaaS services reachable only via private endpoints; `public_network_access_enabled = false` |
| **Chatbot-api not internet-routable** | Internal CAE LB + NSG Deny-Internet-Inbound + no public path on AGW |
| **JWT authentication** | Entra ID RS256 tokens; validated via JWKS on every `/api/chat` call; `aud`, `iss`, `scp` verified |
| **WAF** | OWASP 3.2 + BotManager 1.1 on both listeners; per-IP rate limits on public listener; `/api/` hard-blocked from internet (prod) |
| **Managed Identity** | Every Container App and Function App has its own user-assigned identity with least-privilege RBAC |
| **Customer-Managed Keys** | Key Vault Premium + CMK enabled in prod; purge protection on all Key Vaults |
| **Audit logging** | NSG flow logs (VNet-level) + diagnostic settings on every resource → Log Analytics |
