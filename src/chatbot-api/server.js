'use strict';

// Must be initialised before any other require so auto-instrumentation
// patches the http module before express and the OpenAI SDK are loaded.
const appInsights = require('applicationinsights');
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights
    .setup()                          // reads conn string from env automatically
    .setAutoCollectRequests(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectPerformance(false)
    .setAutoCollectDependencies(true)
    .setUseDiskRetryCaching(false)
    .start();
}

const fs      = require('fs');
const path    = require('path');
const express = require('express');
const jwt     = require('jsonwebtoken');
const jwksRsa = require('jwks-rsa');
const { AzureOpenAI } = require('openai');
const { QueueServiceClient } = require('@azure/storage-queue');
const { SearchClient, AzureKeyCredential } = require('@azure/search-documents');
const { DefaultAzureCredential, getBearerTokenProvider } = require('@azure/identity');

const app = express();
app.use(express.json({ limit: '256kb' }));

const ENDPOINT   = process.env.AZURE_OPENAI_ENDPOINT;
const DEPLOYMENT = process.env.AZURE_OPENAI_CHAT_DEPLOYMENT || 'gpt-4o';
const API_VER    = process.env.AZURE_OPENAI_API_VERSION    || '2024-10-21';

// When true, the last user message text is included in telemetry.
// Disabled by default — enable only after verifying data-residency and
// privacy/consent requirements for your deployment.
const LOG_MESSAGE_CONTENT = process.env.LOG_MESSAGE_CONTENT === 'true';

// When true, the full OpenAI request payload (system prompt + all messages) and
// the assembled response text are written to telemetry as OpenAIRequest /
// OpenAIResponse events. Implies full content logging — enable with care.
const LOG_OPENAI_IO = process.env.LOG_OPENAI_IO === 'true';

// When true, a JSON evaluation job is enqueued to eval-jobs after every completed chat.
// The Function App picks it up and forwards it to the Foundry Hosted Agent for scoring.
const EVAL_QUEUE_ENABLED   = process.env.EVAL_QUEUE_ENABLED === 'true';
const STORAGE_ACCOUNT_NAME = process.env.STORAGE_ACCOUNT_NAME;
const EVAL_JOBS_QUEUE_NAME = process.env.EVAL_JOBS_QUEUE_NAME || 'eval-jobs';

if (EVAL_QUEUE_ENABLED && !STORAGE_ACCOUNT_NAME) {
  throw new Error('STORAGE_ACCOUNT_NAME must be set when EVAL_QUEUE_ENABLED=true');
}

// ── RAG / retrieval config ─────────────────────────────────────────────────────
const SEARCH_ENDPOINT        = process.env.AZURE_AI_SEARCH_ENDPOINT;
const SEARCH_INDEX_NAME      = process.env.AZURE_AI_SEARCH_INDEX_NAME || 'foundry-chunks';
const EMBEDDING_DEPLOYMENT   = process.env.AZURE_OPENAI_EMBEDDING_DEPLOYMENT;
const RETRIEVAL_TOP_K        = parseInt(process.env.RETRIEVAL_TOP_K || '5', 10);

// ── Telemetry ─────────────────────────────────────────────────────────────────
// Fire-and-forget custom events written to Application Insights → Log Analytics.
// All property values are coerced to strings so KQL tostring() is not needed.
// Schema: customEvents | where name startswith "Chat"
function track(name, props) {
  const c = appInsights.defaultClient;
  if (!c) return;
  try {
    c.trackEvent({
      name,
      properties: Object.fromEntries(Object.entries(props).map(([k, v]) => [k, String(v ?? '')])),
    });
  } catch { /* non-critical — never block the request path */ }
}

// ── Workflow definitions ───────────────────────────────────────────────────────
// Loaded once at startup from ./workflows/*.json.
// Each file must contain: { id, name, description, system_prompt, parameters }
// Clients may request a workflow by id; the server validates the id and rejects
// anything not in this map — no arbitrary prompt injection is possible.
const workflowsDir = path.join(__dirname, 'workflows');
const workflows    = new Map();

for (const file of fs.readdirSync(workflowsDir).filter(f => f.endsWith('.json'))) {
  const w = JSON.parse(fs.readFileSync(path.join(workflowsDir, file), 'utf8'));
  if (!w.id || !w.name || !w.system_prompt) {
    throw new Error(`Workflow file ${file} is missing required fields (id, name, system_prompt)`);
  }
  workflows.set(w.id, w);
}

const defaultWorkflow = workflows.get('default');
if (!defaultWorkflow) throw new Error('A workflow with id "default" is required in ./workflows/');

console.log(`Loaded ${workflows.size} workflow(s): ${[...workflows.keys()].join(', ')}`);

// Maximum number of conversation turns accepted per request
const MAX_MESSAGES = 40;
// Maximum characters per individual message content
const MAX_CONTENT_LENGTH = 8000;

// ── In-process rate limiter — last-resort defence behind WAF ─────────────────
// The AGW WAF is the authoritative per-client-IP rate limiter (SocketAddr-based).
// This limiter adds per-connection-source protection inside the pod. It uses the
// TCP socket address (not X-Forwarded-For) to avoid header-spoofing bypasses.
const RATE_LIMIT = parseInt(process.env.RATE_LIMIT_RPM || '20', 10);
const rateLimitMap = new Map();
setInterval(() => rateLimitMap.clear(), 60_000);

function checkRateLimit(socketAddr) {
  const count = (rateLimitMap.get(socketAddr) || 0) + 1;
  rateLimitMap.set(socketAddr, count);
  return count <= RATE_LIMIT;
}

// ── JWT authentication middleware ─────────────────────────────────────────────
//
// Validates Entra ID Bearer tokens on every /api/* request.
// Skipped entirely when AZURE_TENANT_ID is not set (local dev without auth).
//
// Token requirements:
//   aud  — must equal AZURE_API_CLIENT_ID (the API app registration client ID)
//   iss  — must equal https://login.microsoftonline.com/<tenant>/v2.0
//   scp  — must contain "Chat.Read"
//   alg  — RS256 (Entra ID v2 default)

const TENANT_ID     = process.env.AZURE_TENANT_ID;
const API_CLIENT_ID = process.env.AZURE_API_CLIENT_ID;
const AUTH_ENABLED  = Boolean(TENANT_ID && API_CLIENT_ID);

let jwksClient;
if (AUTH_ENABLED) {
  jwksClient = jwksRsa({
    jwksUri:   `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`,
    cache:     true,
    rateLimit: true,
    // Keys are valid for 24 h in Entra ID; fetch eagerly every 10 h to avoid
    // serving stale keys after a rotation.
    cacheMaxAge:      10 * 60 * 60 * 1000,
    cacheMaxEntries:  5,
  });
}

function getSigningKey(header, callback) {
  jwksClient.getSigningKey(header.kid, (err, key) => {
    if (err) return callback(err);
    callback(null, key.getPublicKey());
  });
}

function authenticate(req, res, next) {
  if (!AUTH_ENABLED) return next();   // local dev — skip auth

  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Authorization header required' });
  }

  const token = authHeader.slice(7);
  jwt.verify(
    token,
    getSigningKey,
    {
      audience:   API_CLIENT_ID,
      issuer:     `https://login.microsoftonline.com/${TENANT_ID}/v2.0`,
      algorithms: ['RS256'],
    },
    (err, decoded) => {
      if (err) {
        // Log detail server-side; never leak JWT internals to the client
        console.warn('JWT validation failed:', err.message);
        return res.status(401).json({ error: 'Invalid or expired token' });
      }

      // Require the Chat.Read scope to be present in the token
      const scopes = (decoded.scp || '').split(' ');
      if (!scopes.includes('Chat.Read')) {
        return res.status(403).json({ error: 'Insufficient scope' });
      }

      req.user = { oid: decoded.oid, name: decoded.name };
      next();
    },
  );
}

// Lazy-init client so the server starts without credentials during local dev
let _client;
function client() {
  if (!_client) {
    const credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID,
    });
    const tokenProvider = getBearerTokenProvider(
      credential,
      'https://cognitiveservices.azure.com/.default',
    );
    _client = new AzureOpenAI({ endpoint: ENDPOINT, azureADTokenProvider: tokenProvider, apiVersion: API_VER });
  }
  return _client;
}

// Lazy-init search client — reuse the same managed-identity credential
let _searchClient;
function searchClient() {
  if (!_searchClient) {
    const credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID,
    });
    _searchClient = new SearchClient(SEARCH_ENDPOINT, SEARCH_INDEX_NAME, credential);
  }
  return _searchClient;
}

// Embeds the user query and fetches top-k chunks from AI Search.
// Returns a formatted string to inject into the system prompt, or '' on failure.
async function retrieveContext(userQuery, topK) {
  if (!SEARCH_ENDPOINT || !EMBEDDING_DEPLOYMENT) return '';
  try {
    const embResp = await client().embeddings.create({
      model: EMBEDDING_DEPLOYMENT,
      input: userQuery,
      dimensions: 1536,
    });
    const vector = embResp.data[0].embedding;

    const results = await searchClient().search(userQuery, {
      vectorSearchOptions: {
        queries: [{
          kind:      'vector',
          vector,
          kNearestNeighborsCount: topK,
          fields:    ['content_vector'],
        }],
      },
      queryType:    'semantic',
      semanticSearchOptions: { configurationName: 'default' },
      select:       ['content', 'source'],
      top:          topK,
    });

    const chunks = [];
    for await (const r of results.results) {
      chunks.push(`[Source: ${r.document.source}]\n${r.document.content}`);
    }
    if (!chunks.length) return '';
    return `## Retrieved Context\n\n${chunks.join('\n\n---\n\n')}`;
  } catch (err) {
    console.warn('Retrieval failed (degrading gracefully):', err.message);
    return '';
  }
}

// Lazy-init queue client — same managed-identity pattern as the OpenAI client
let _queueClient;
function queueClient() {
  if (!_queueClient) {
    const credential = new DefaultAzureCredential({
      managedIdentityClientId: process.env.AZURE_CLIENT_ID,
    });
    const queueServiceClient = new QueueServiceClient(
      `https://${STORAGE_ACCOUNT_NAME}.queue.core.windows.net`,
      credential,
    );
    _queueClient = queueServiceClient.getQueueClient(EVAL_JOBS_QUEUE_NAME);
  }
  return _queueClient;
}

// Azure Storage Queue hard limit: 64 KB per message (base64-encoded).
// Base64 expands 4:3, so the raw JSON must stay under 64*1024*3/4 = 49152 bytes.
// Long conversations are trimmed from the oldest end; the evaluator only needs
// recent context to assess relevance and groundedness of the final response.
const QUEUE_MAX_RAW_BYTES = 49000;
const EVAL_RESPONSE_MAX_CHARS = 3000;

function buildEvalPayload(requestId, sessionId, userId, workflowId, messages, assistantResponse, retrievedContext) {
  const responseText  = assistantResponse.slice(0, EVAL_RESPONSE_MAX_CHARS);
  // Match agent.py _MAX_RETRIEVED_CONTEXT_CHARS limit
  const contextText   = (retrievedContext || '').slice(0, 20_000);
  let trimmedMessages = messages;
  while (trimmedMessages.length > 1) {
    const json = JSON.stringify({
      request_id:         requestId,
      session_id:         sessionId,
      user_id:            userId,
      workflow_id:        workflowId,
      messages:           trimmedMessages,
      assistant_response: responseText,
      retrieved_context:  contextText,
    });
    if (Buffer.byteLength(json, 'utf8') <= QUEUE_MAX_RAW_BYTES) {
      return Buffer.from(json).toString('base64');
    }
    trimmedMessages = trimmedMessages.slice(Math.ceil(trimmedMessages.length / 2));
  }
  return Buffer.from(JSON.stringify({
    request_id:         requestId,
    session_id:         sessionId,
    user_id:            userId,
    workflow_id:        workflowId,
    messages:           trimmedMessages,
    assistant_response: responseText,
    retrieved_context:  contextText,
  })).toString('base64');
}

// Fire-and-forget: enqueue an evaluation job without blocking the SSE response.
function enqueueEval(requestId, sessionId, userId, workflowId, messages, assistantResponse, retrievedContext) {
  Promise.resolve().then(async () => {
    try {
      const encoded = buildEvalPayload(requestId, sessionId, userId, workflowId, messages, assistantResponse, retrievedContext);
      await queueClient().sendMessage(encoded);
    } catch (err) {
      console.error('Eval enqueue error:', err.message);
      track('EvalEnqueueError', { requestId, sessionId, errorType: err.constructor?.name ?? 'Error' });
    }
  });
}

// ── Health check — AGW and Container Apps liveness probe ──────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// ── Workflow catalogue — returns public metadata only (no system prompts) ──────
app.get('/api/workflows', (_req, res) => {
  const list = [...workflows.values()].map(({ id, name, description }) => ({ id, name, description }));
  res.json(list);
});

// ── Chat completions with SSE streaming ───────────────────────────────────────
app.post('/api/chat', authenticate, async (req, res) => {
  const socketAddr = req.socket.remoteAddress;
  if (!checkRateLimit(socketAddr)) {
    return res.status(429).json({ error: 'Too many requests — try again in a minute.' });
  }

  // workflowId is validated against the server-side workflow map.
  // Unknown or missing ids fall back to the default workflow.
  const { messages, workflowId, sessionId: rawSessionId } = req.body;
  const workflow = (workflowId && workflows.has(workflowId))
    ? workflows.get(workflowId)
    : defaultWorkflow;

  const requestId = crypto.randomUUID();
  const startTime = Date.now();

  // Accept a client-provided sessionId for multi-turn session tracking.
  // Must be a valid UUID v4; any non-conforming value is silently replaced.
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const sessionId = (typeof rawSessionId === 'string' && UUID_RE.test(rawSessionId))
    ? rawSessionId
    : requestId;

  if (!Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }
  if (messages.length > MAX_MESSAGES) {
    return res.status(400).json({ error: `Conversation too long (max ${MAX_MESSAGES} messages)` });
  }

  // Validate shape: only user/assistant roles, string content within length limits
  const valid = messages.every(
    m => ['user', 'assistant'].includes(m.role) &&
         typeof m.content === 'string' &&
         m.content.length <= MAX_CONTENT_LENGTH
  );
  if (!valid) {
    return res.status(400).json({ error: 'invalid message format' });
  }

  track('ChatRequest', {
    requestId,
    sessionId,
    userId:       req.user?.oid  ?? 'anonymous',
    userName:     req.user?.name ?? 'anonymous',
    workflowId:   workflow.id,
    messageCount: messages.length,
    ...(LOG_MESSAGE_CONTENT && {
      lastUserMessage: (messages.filter(m => m.role === 'user').pop()?.content ?? '').slice(0, 500),
    }),
  });

  // RAG retrieval runs before we start streaming so errors return a proper HTTP status.
  const lastUserMessage = messages.filter(m => m.role === 'user').pop()?.content ?? '';
  let retrievedContext = '';
  if (workflow.retrieval_enabled && lastUserMessage) {
    retrievedContext = await retrieveContext(lastUserMessage, RETRIEVAL_TOP_K);
  }

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx/AGW proxy buffering
  res.flushHeaders();

  try {
    const { system_prompt, parameters = {} } = workflow;
    const systemContent = retrievedContext
      ? `${system_prompt}\n\n${retrievedContext}`
      : system_prompt;
    const requestMessages = [{ role: 'system', content: systemContent }, ...messages];
    const openAiStartMs   = Date.now();

    if (LOG_OPENAI_IO) {
      track('OpenAIRequest', {
        requestId,
        model:       DEPLOYMENT,
        workflowId:  workflow.id,
        maxTokens:   parameters.max_tokens  ?? 2048,
        temperature: parameters.temperature ?? 0.7,
        // Full payload truncated to the App Insights property limit (8192 chars)
        request: JSON.stringify(requestMessages).slice(0, 8000),
      });
    }

    let usage = null;
    const stream = await client().chat.completions.create({
      model:          DEPLOYMENT,
      messages:       requestMessages,
      stream:         true,
      stream_options: { include_usage: true },
      max_tokens:     parameters.max_tokens  ?? 2048,
      temperature:    parameters.temperature ?? 0.7,
    });

    let responseText = '';
    const captureResponse = LOG_OPENAI_IO || EVAL_QUEUE_ENABLED;
    for await (const chunk of stream) {
      // The final chunk (with include_usage) carries usage only — no content delta
      if (chunk.usage) { usage = chunk.usage; continue; }
      const delta = chunk.choices[0]?.delta?.content;
      if (delta) {
        if (captureResponse) responseText += delta;
        res.write(`data: ${JSON.stringify({ content: delta })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');

    if (LOG_OPENAI_IO) {
      track('OpenAIResponse', {
        requestId,
        model:            DEPLOYMENT,
        workflowId:       workflow.id,
        openAiDurationMs: Date.now() - openAiStartMs,
        promptTokens:     usage?.prompt_tokens     ?? -1,
        completionTokens: usage?.completion_tokens ?? -1,
        totalTokens:      usage?.total_tokens      ?? -1,
        response:         responseText.slice(0, 8000),
      });
    }

    track('ChatComplete', {
      requestId,
      sessionId,
      userId:           req.user?.oid ?? 'anonymous',
      workflowId:       workflow.id,
      durationMs:       Date.now() - startTime,
      promptTokens:     usage?.prompt_tokens     ?? -1,
      completionTokens: usage?.completion_tokens ?? -1,
      totalTokens:      usage?.total_tokens      ?? -1,
    });

    if (EVAL_QUEUE_ENABLED && responseText) {
      enqueueEval(
        requestId,
        sessionId,
        req.user?.oid ?? 'anonymous',
        workflow.id,
        messages,
        responseText,
        retrievedContext,
      );
    }
  } catch (err) {
    // Log full error server-side; send only a generic message to the client
    console.error('OpenAI error:', err.message);
    track('ChatError', {
      requestId,
      userId:     req.user?.oid ?? 'anonymous',
      workflowId: workflow.id,
      durationMs: Date.now() - startTime,
      errorType:  err.constructor?.name ?? 'Error',
    });
    res.write(`data: ${JSON.stringify({ error: 'An error occurred. Please try again.' })}\n\n`);
  }

  res.end();
});

const PORT = parseInt(process.env.PORT || '8080', 10);
app.listen(PORT, () => {
  console.log(`Chatbot API listening on :${PORT}  deployment=${DEPLOYMENT}  auth=${AUTH_ENABLED}`);
});
