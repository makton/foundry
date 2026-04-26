"""
Azure AI Foundry Hosted Agent — Chat Accuracy Evaluator

Implements the Foundry Invocations protocol:
  POST /invocations  — evaluate a completed chat session
  GET  /health       — liveness probe

The agent is stateless: it receives the full conversation payload from the
Function App trigger, evaluates it, and returns the scores. Persistence is
handled by the caller (eval_trigger.py writes to CosmosDB).
"""

import logging
import os

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, field_validator

from evaluator import evaluate

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="accuracy-evaluator", docs_url=None, redoc_url=None)

_MAX_MESSAGES       = 40
_MAX_CONTENT_CHARS  = 8000
_MAX_RESPONSE_CHARS = 4000
_MAX_ID_CHARS       = 256


class ChatMessage(BaseModel):
    role: str
    content: str

    @field_validator("role")
    @classmethod
    def role_must_be_valid(cls, v: str) -> str:
        if v not in {"user", "assistant"}:
            raise ValueError(f"Invalid role: {v}")
        return v

    @field_validator("content")
    @classmethod
    def content_length(cls, v: str) -> str:
        if len(v) > _MAX_CONTENT_CHARS:
            raise ValueError(f"Message content too long (max {_MAX_CONTENT_CHARS} chars)")
        return v


class InvocationRequest(BaseModel):
    request_id:         str = ""
    session_id:         str
    user_id:            str = "anonymous"
    workflow_id:        str = "default"
    messages:           list[ChatMessage]
    assistant_response: str

    @field_validator("request_id", "session_id", "user_id", "workflow_id")
    @classmethod
    def id_length(cls, v: str) -> str:
        if len(v) > _MAX_ID_CHARS:
            raise ValueError(f"Field too long (max {_MAX_ID_CHARS} chars)")
        return v

    @field_validator("messages")
    @classmethod
    def messages_limit(cls, v: list) -> list:
        if len(v) > _MAX_MESSAGES:
            raise ValueError(f"Too many messages (max {_MAX_MESSAGES})")
        return v

    @field_validator("assistant_response")
    @classmethod
    def response_length(cls, v: str) -> str:
        if len(v) > _MAX_RESPONSE_CHARS:
            raise ValueError(f"assistant_response too long (max {_MAX_RESPONSE_CHARS} chars)")
        return v


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/invocations")
async def invocations(payload: InvocationRequest) -> JSONResponse:
    if not payload.messages:
        raise HTTPException(status_code=400, detail="messages array is required")
    if not payload.assistant_response.strip():
        raise HTTPException(status_code=400, detail="assistant_response is required")

    logger.info(
        "Evaluating request=%s session=%s workflow=%s messages=%d",
        payload.request_id or "(none)",
        payload.session_id,
        payload.workflow_id,
        len(payload.messages),
    )

    try:
        evaluation = evaluate(
            messages=[m.model_dump() for m in payload.messages],
            assistant_response=payload.assistant_response,
        )
    except Exception as exc:
        logger.exception("Evaluation failed for session=%s: %s", payload.session_id, exc)
        raise HTTPException(status_code=500, detail="Evaluation failed") from exc

    logger.info(
        "Evaluation complete session=%s overall=%.4f",
        payload.session_id,
        evaluation["overall"],
    )

    return JSONResponse(content={
        "request_id": payload.request_id,
        "session_id": payload.session_id,
        "evaluation": evaluation,
    })


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error: %s", exc)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})
