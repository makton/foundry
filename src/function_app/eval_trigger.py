"""
QueueTrigger function: eval-jobs → Foundry Hosted Agent → CosmosDB chat-evaluations

Flow:
  1. Storage Queue message arrives (base64 JSON, enqueued by chatbot-api)
  2. Decode and parse the payload
  3. POST to the Foundry Hosted Agent /invocations endpoint (bearer token via ML scope)
  4. Write the combined evaluation record to CosmosDB chat-evaluations container
"""

import base64
import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
import httpx
from azure.cosmos import CosmosClient, exceptions as cosmos_exc
from azure.identity import ManagedIdentityCredential

logger = logging.getLogger(__name__)

_FOUNDRY_AGENT_ENDPOINT = os.environ.get("FOUNDRY_AGENT_ENDPOINT", "")
_COSMOSDB_ENDPOINT      = os.environ["COSMOSDB_ENDPOINT"]
_COSMOSDB_DATABASE      = os.environ["COSMOSDB_DATABASE_NAME"]
_COSMOSDB_CONTAINER     = os.environ.get("COSMOSDB_EVAL_CONTAINER", "chat-evaluations")
_AZURE_CLIENT_ID        = os.environ.get("AZURE_CLIENT_ID")

# ML scope for Foundry Agent endpoint authentication
_ML_SCOPE = "https://ml.azure.com/.default"

_credential: ManagedIdentityCredential | None = None
_cosmos_client: CosmosClient | None = None


def _get_credential() -> ManagedIdentityCredential:
    global _credential
    if _credential is None:
        _credential = ManagedIdentityCredential(client_id=_AZURE_CLIENT_ID)
    return _credential


def _get_cosmos_container():
    global _cosmos_client
    if _cosmos_client is None:
        _cosmos_client = CosmosClient(_COSMOSDB_ENDPOINT, credential=_get_credential())
    db        = _cosmos_client.get_database_client(_COSMOSDB_DATABASE)
    container = db.get_container_client(_COSMOSDB_CONTAINER)
    return container


def _call_foundry_agent(payload: dict) -> dict:
    """POST the evaluation payload to the Foundry Hosted Agent and return the result."""
    token = _get_credential().get_token(_ML_SCOPE).token
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }
    with httpx.Client(timeout=60.0) as http:
        response = http.post(
            f"{_FOUNDRY_AGENT_ENDPOINT}/invocations",
            json=payload,
            headers=headers,
        )
        response.raise_for_status()
        return response.json()


bp = func.Blueprint()


@bp.queue_trigger(
    arg_name="msg",
    queue_name="%EVAL_JOBS_QUEUE_NAME%",
    connection="EvalQueueConnection",
)
def eval_trigger(msg: func.QueueMessage) -> None:
    raw = msg.get_body().decode("utf-8")

    # Messages from chatbot-api are base64-encoded JSON
    try:
        decoded = base64.b64decode(raw).decode("utf-8")
        payload = json.loads(decoded)
    except Exception:
        # Fall back to plain JSON (e.g. messages injected manually for testing)
        payload = json.loads(raw)

    request_id  = payload.get("request_id", "")
    session_id  = payload.get("session_id", "unknown")
    user_id     = payload.get("user_id",    "anonymous")
    workflow_id = payload.get("workflow_id", "default")

    # Fallback: if no request_id provided (older payload schema), use session_id
    doc_id = request_id or session_id

    logger.info("eval_trigger: request=%s session=%s workflow=%s", doc_id, session_id, workflow_id)

    if not _FOUNDRY_AGENT_ENDPOINT:
        logger.error("FOUNDRY_AGENT_ENDPOINT is not configured — skipping evaluation")
        return

    try:
        result = _call_foundry_agent(payload)
    except httpx.HTTPStatusError as exc:
        logger.error(
            "Foundry Agent returned %d for session=%s: %s",
            exc.response.status_code, session_id, exc.response.text,
        )
        raise
    except Exception as exc:
        logger.exception("Foundry Agent call failed for session=%s: %s", session_id, exc)
        raise

    evaluation = result.get("evaluation", {})
    logger.info(
        "eval_trigger: session=%s overall=%.4f",
        session_id, evaluation.get("overall", -1),
    )

    record = {
        "id":                doc_id,       # unique per request turn; partition key is session_id
        "request_id":        doc_id,
        "session_id":        session_id,
        "user_id":           user_id,
        "workflow_id":       workflow_id,
        "messages":          payload.get("messages", []),
        "assistant_response": payload.get("assistant_response", ""),
        "groundedness":      evaluation.get("groundedness"),
        "relevance":         evaluation.get("relevance"),
        "coherence":         evaluation.get("coherence"),
        "overall":           evaluation.get("overall"),
        "reasoning":         evaluation.get("reasoning", ""),
        "evaluated_at":      datetime.now(timezone.utc).isoformat(),
    }

    try:
        _get_cosmos_container().upsert_item(record)
        logger.info("eval_trigger: written to CosmosDB request=%s session=%s", doc_id, session_id)
    except cosmos_exc.CosmosHttpResponseError as exc:
        logger.error("CosmosDB write failed session=%s: %s", session_id, exc.message)
        raise
