'use strict';

const express = require('express');
const path = require('path');
const { AzureOpenAI } = require('openai');
const { DefaultAzureCredential, getBearerTokenProvider } = require('@azure/identity');

const app = express();
app.use(express.json({ limit: '1mb' }));

const ENDPOINT   = process.env.AZURE_OPENAI_ENDPOINT;
const DEPLOYMENT = process.env.AZURE_OPENAI_CHAT_DEPLOYMENT || 'gpt-4o';
const API_VER    = process.env.AZURE_OPENAI_API_VERSION    || '2024-10-21';
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

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no'); // Disable nginx/AGW proxy buffering
  res.flushHeaders();

  try {
    const stream = await client().chat.completions.create({
      model: DEPLOYMENT,
      messages: [
        { role: 'system', content: systemPrompt || SYSTEM_PROMPT },
        ...messages,
      ],
      stream: true,
      max_tokens: 2048,
      temperature: 0.7,
    });

    for await (const chunk of stream) {
      const delta = chunk.choices[0]?.delta?.content;
      if (delta) {
        res.write(`data: ${JSON.stringify({ content: delta })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');
  } catch (err) {
    console.error('OpenAI error:', err.message);
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
