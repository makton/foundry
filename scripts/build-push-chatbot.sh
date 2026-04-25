#!/usr/bin/env bash
# Build and push the chatbot-ui and chatbot-api Docker images to Azure Container Registry.
#
# Usage:
#   ./scripts/build-push-chatbot.sh <acr-name> [image-tag]
#
# Examples:
#   ./scripts/build-push-chatbot.sh acrfoundrydev001
#   ./scripts/build-push-chatbot.sh acrfoundrydev001 v1.2.0
#
# After running this script, set the image variables in your .tfvars and re-apply:
#   terraform apply -var-file=environments/dev.tfvars

set -euo pipefail

ACR_NAME="${1:-}"
IMAGE_TAG="${2:-latest}"

if [[ -z "$ACR_NAME" ]]; then
  echo "Error: ACR name is required."
  echo "Usage: $0 <acr-name> [image-tag]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/../src"

UI_IMAGE="${ACR_NAME}.azurecr.io/chatbot-ui:${IMAGE_TAG}"
API_IMAGE="${ACR_NAME}.azurecr.io/chatbot-api:${IMAGE_TAG}"

echo "==> ACR:        $ACR_NAME"
echo "==> UI image:   $UI_IMAGE"
echo "==> API image:  $API_IMAGE"
echo ""

echo "==> Logging in to ACR..."
az acr login --name "$ACR_NAME"

echo "==> Building chatbot-ui (Nginx/React)..."
docker build \
  --platform linux/amd64 \
  -t "$UI_IMAGE" \
  "$SRC_DIR/chatbot-ui"

echo "==> Building chatbot-api (Node/Express)..."
docker build \
  --platform linux/amd64 \
  -t "$API_IMAGE" \
  "$SRC_DIR/chatbot-api"

echo "==> Pushing images..."
docker push "$UI_IMAGE"
docker push "$API_IMAGE"

echo ""
echo "Done. Add the following to your .tfvars and run terraform apply:"
echo ""
echo "    chatbot_ui_image  = \"$UI_IMAGE\""
echo "    chatbot_api_image = \"$API_IMAGE\""
echo ""
