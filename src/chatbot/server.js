'use strict';

// Must be initialised before any other require for auto-instrumentation
const appInsights = require('applicationinsights');
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights
    .setup()
    .setAutoCollectRequests(true)
    .setAutoCollectExceptions(true)
    .setAutoCollectPerformance(false)
    .setAutoCollectDependencies(true)
    .setUseDiskRetryCaching(false)
    .start();
}

const express = require('express');
const path = require('path');
const { AzureOpenAI } = require('openai');
const { DefaultAzureCredential, getBearerTokenProvider } = require('@azure/identity');

const app = express();
app.use(express.json({ limit: '1mb' }));

const ENDPOINT   = process.env.AZURE_OPENAI_ENDPOINT;
const DEPLOYMENT = process.env.AZURE_OPENAI_CHAT_DEPLOYMENT || 'gpt-4o';
const API_VER    = process.env.AZURE_OPENAI_API_VERSION    || '2024-10-21';

const LOG_MESSAGE_CONTENT = process.env.LOG_MESSAGE_CONTENT === 'true';
const LOG_OPENAI_IO       = process.env.LOG_OPENAI_IO === 'true';

function track(name, props) {
  const c = appInsights.defaultClient;
  if (!c) return;
  try {
    c.trackEvent({
      name,
      properties: Object.fromEntries(Object.entries(props).map(([k, v]) => [k, String(v ?? '')])),
    });
  } catch { /* non-critical */ }
}

const SYSTEM_PROMPT = process.env.CHATBOT_SYSTEM_PROMPT ||
  'You are a helpful AI assistant for an Azure AI Foundry platform. ' +
  'Answer clearly and concisely. When referencing documents, cite your sources.';

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

// ── Health check — AGW and Container Apps liveness probe ──────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', deployment: DEPLOYMENT });
});

// ── Chat completions with SSE streaming ───────────────────────────────────────
app.post('/api/chat', async (req, res) => {
  const { messages, systemPrompt } = req.body;

  if (!Array.isArray(messages) || messages.length === 0) {
    return res.status(400).json({ error: 'messages array is required' });
  }

  // Validate message shape to prevent prompt injection from client
  const safe = messages.every(m => ['user', 'assistant'].includes(m.role) && typeof m.content === 'string');
  if (!safe) {
    return res.status(400).json({ error: 'invalid message format' });
  }

  const requestId = crypto.randomUUID();
  const startTime = Date.now();

  track('ChatRequest', {
    requestId,
    userId: 'anonymous',
    messageCount: messages.length,
    ...(LOG_MESSAGE_CONTENT && {
      lastUserMessage: (messages.filter(m => m.role === 'user').pop()?.content ?? '').slice(0, 500),
    }),
  });

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx/AGW proxy buffering
  res.flushHeaders();

  try {
    const requestMessages = [{ role: 'system', content: systemPrompt || SYSTEM_PROMPT }, ...messages];
    const openAiStartMs   = Date.now();

    if (LOG_OPENAI_IO) {
      track('OpenAIRequest', {
        requestId,
        model:       DEPLOYMENT,
        maxTokens:   2048,
        temperature: 0.7,
        request:     JSON.stringify(requestMessages).slice(0, 8000),
      });
    }

    let usage = null;
    let responseText = '';
    const stream = await client().chat.completions.create({
      model:          DEPLOYMENT,
      messages:       requestMessages,
      stream:         true,
      stream_options: { include_usage: true },
      max_tokens:     2048,
      temperature:    0.7,
    });

    for await (const chunk of stream) {
      if (chunk.usage) { usage = chunk.usage; continue; }
      const delta = chunk.choices[0]?.delta?.content;
      if (delta) {
        if (LOG_OPENAI_IO) responseText += delta;
        res.write(`data: ${JSON.stringify({ content: delta })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');

    if (LOG_OPENAI_IO) {
      track('OpenAIResponse', {
        requestId,
        model:            DEPLOYMENT,
        openAiDurationMs: Date.now() - openAiStartMs,
        promptTokens:     usage?.prompt_tokens     ?? -1,
        completionTokens: usage?.completion_tokens ?? -1,
        totalTokens:      usage?.total_tokens      ?? -1,
        response:         responseText.slice(0, 8000),
      });
    }

    track('ChatComplete', {
      requestId,
      userId:           'anonymous',
      durationMs:       Date.now() - startTime,
      promptTokens:     usage?.prompt_tokens     ?? -1,
      completionTokens: usage?.completion_tokens ?? -1,
      totalTokens:      usage?.total_tokens      ?? -1,
    });
  } catch (err) {
    console.error('OpenAI error:', err.message);
    track('ChatError', {
      requestId,
      userId:     'anonymous',
      durationMs: Date.now() - startTime,
      errorType:  err.constructor?.name ?? 'Error',
    });
    res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
  }

  res.end();
});

// ── Serve built React app ─────────────────────────────────────────────────────
app.use(express.static(path.join(__dirname, 'public')));
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

const PORT = parseInt(process.env.PORT || '8080', 10);
app.listen(PORT, () => {
  console.log(`Chatbot server listening on :${PORT}  deployment=${DEPLOYMENT}`);
});
