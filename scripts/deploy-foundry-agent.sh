#!/usr/bin/env bash
# deploy-foundry-agent.sh — Build, push, and deploy the accuracy-evaluator Foundry Hosted Agent
#
# Prerequisites:
#   - Azure CLI (az) with azure-ai-ml extension: az extension add -n azure-ai-ml
#   - Docker with buildx enabled
#   - Logged in to Azure: az login
#   - Logged in to ACR: done automatically by this script
#
# Required env vars:
#   FOUNDRY_WORKSPACE_NAME   Name of the AI Foundry / Azure ML workspace (the Foundry Hub or Project)
#   RESOURCE_GROUP           Resource group containing the workspace
#   ACR_LOGIN_SERVER         e.g. acrfoundrydev001.azurecr.io
#
# Optional env vars:
#   IMAGE_TAG                Docker image tag (default: git short-SHA or "latest")
#   AGENT_INSTANCE_TYPE      Azure ML instance type (default: Standard_DS1_v2)
#   AGENT_INSTANCE_COUNT     Number of instances (default: 1)

set -euo pipefail

: "${FOUNDRY_WORKSPACE_NAME:?FOUNDRY_WORKSPACE_NAME is required}"
: "${RESOURCE_GROUP:?RESOURCE_GROUP is required}"
: "${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER is required}"

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo latest)}"
AGENT_INSTANCE_TYPE="${AGENT_INSTANCE_TYPE:-Standard_DS1_v2}"
AGENT_INSTANCE_COUNT="${AGENT_INSTANCE_COUNT:-1}"

AGENT_NAME="accuracy-evaluator"
IMAGE="${ACR_LOGIN_SERVER}/${AGENT_NAME}:${IMAGE_TAG}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_YAML="$(mktemp /tmp/deploy-XXXXXX.yaml)"

cleanup() { rm -f "${DEPLOY_YAML}"; }
trap cleanup EXIT

echo "==> Installing azure-ai-ml CLI extension (idempotent)"
az extension add --name azure-ai-ml --upgrade --yes 2>/dev/null || true

echo "==> Building image (linux/amd64): ${IMAGE}"
docker build \
  --platform linux/amd64 \
  --tag "${IMAGE}" \
  "${REPO_ROOT}/src/foundry-agent"

echo "==> Authenticating to ACR: ${ACR_LOGIN_SERVER}"
az acr login --name "${ACR_LOGIN_SERVER%%.*}"

echo "==> Pushing image: ${IMAGE}"
docker push "${IMAGE}"

# Create or update the online endpoint (idempotent)
echo "==> Creating/updating online endpoint: ${AGENT_NAME}"
az ml online-endpoint create \
  --resource-group  "${RESOURCE_GROUP}" \
  --workspace-name  "${FOUNDRY_WORKSPACE_NAME}" \
  --name            "${AGENT_NAME}" \
  --auth-mode       aml_token \
  2>/dev/null || \
az ml online-endpoint update \
  --resource-group  "${RESOURCE_GROUP}" \
  --workspace-name  "${FOUNDRY_WORKSPACE_NAME}" \
  --name            "${AGENT_NAME}"

# Write the deployment YAML — defines the container, routes, and instance config
cat > "${DEPLOY_YAML}" <<YAML
\$schema: https://azuremlschemas.azureedge.net/latest/managedOnlineDeployment.schema.json
name: blue
endpoint_name: ${AGENT_NAME}
environment:
  image: ${IMAGE}
  inference_config:
    liveness_route:
      port: 8080
      path: /health
    readiness_route:
      port: 8080
      path: /health
    scoring_route:
      port: 8080
      path: /invocations
instance_type: ${AGENT_INSTANCE_TYPE}
instance_count: ${AGENT_INSTANCE_COUNT}
environment_variables:
  AZURE_OPENAI_EVAL_DEPLOYMENT: gpt-4o
  AZURE_OPENAI_API_VERSION: "2024-10-21"
YAML

echo "==> Deploying (this may take 5-10 minutes)..."
az ml online-deployment create \
  --resource-group  "${RESOURCE_GROUP}" \
  --workspace-name  "${FOUNDRY_WORKSPACE_NAME}" \
  --file            "${DEPLOY_YAML}" \
  --all-traffic

echo ""
ENDPOINT_URL="$(az ml online-endpoint show \
  --resource-group  "${RESOURCE_GROUP}" \
  --workspace-name  "${FOUNDRY_WORKSPACE_NAME}" \
  --name            "${AGENT_NAME}" \
  --query "scoring_uri" \
  --output tsv)"

echo "==> Deployment complete."
echo ""
echo "Endpoint URL (scoring_uri):"
echo "  ${ENDPOINT_URL}"
echo ""
echo "Next step: set foundry_agent_endpoint in terraform/environments/dev.tfvars:"
echo "  foundry_agent_endpoint = \"${ENDPOINT_URL}\""
echo ""
echo "Then re-apply Terraform to inject the URL into the Function App:"
echo "  terraform -chdir=terraform apply -var-file=environments/dev.tfvars"
