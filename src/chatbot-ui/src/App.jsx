import { useState, useCallback } from 'react';
import { useMsal } from '@azure/msal-react';
import ChatWindow from './components/ChatWindow.jsx';
import InputBar from './components/InputBar.jsx';

export default function App({ apiScope }) {
  const [messages, setMessages]   = useState([]);
  const [streaming, setStreaming] = useState(false);
  const [error, setError]         = useState(null);

  const { instance, accounts } = useMsal();
  const isAuthenticated = accounts.length > 0;

  // ── Token acquisition ────────────────────────────────────────────────────────
  // Tries silent acquisition first; falls back to popup if the token has expired
  // or the user needs to re-consent. Returns null when auth is disabled.
  const acquireToken = useCallback(async () => {
    if (!apiScope) return null;    // auth disabled (local dev)
    if (!isAuthenticated) {
      await instance.loginPopup({ scopes: [apiScope] });
      return null;                 // page will re-render once MSAL updates accounts
    }
    try {
      const { accessToken } = await instance.acquireTokenSilent({
        scopes:  [apiScope],
        account: accounts[0],
      });
      return accessToken;
    } catch {
      await instance.acquireTokenPopup({ scopes: [apiScope], account: accounts[0] });
      return null;
    }
  }, [instance, accounts, apiScope, isAuthenticated]);

  // ── Login gate — shown when auth is required but the user is not signed in ──
  if (apiScope && !isAuthenticated) {
    return (
      <div className="app">
        <header className="app-header">
          <div className="header-brand">
            <svg className="header-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <path d="M12 2L2 7l10 5 10-5-10-5z" />
              <path d="M2 17l10 5 10-5" />
              <path d="M2 12l10 5 10-5" />
            </svg>
            <span>AI Foundry Chat</span>
          </div>
        </header>
        <main className="app-main">
          <div className="chat-window chat-empty">
            <div className="empty-state">
              <div className="empty-icon" aria-hidden="true">🔐</div>
              <h2>Sign in to continue</h2>
              <p>Your organisation requires authentication to use this app.</p>
              <button
                className="btn-signin"
                onClick={() => instance.loginPopup({ scopes: [apiScope] })}
              >
                Sign in with Microsoft
              </button>
            </div>
          </div>
        </main>
      </div>
    );
  }

  // ── Chat ─────────────────────────────────────────────────────────────────────
  const sendMessage = useCallback(async (text) => {
    if (!text.trim() || streaming) return;

    const userMsg = { role: 'user',      content: text, id: crypto.randomUUID() };
    const asstMsg = { role: 'assistant', content: '',   id: crypto.randomUUID() };

    const history = messages.map(({ role, content }) => ({ role, content }));
    history.push({ role: 'user', content: text });

    setMessages(prev => [...prev, userMsg, asstMsg]);
    setStreaming(true);
    setError(null);

    try {
      const token = await acquireToken();

      const response = await fetch('/api/chat', {
        method:  'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token && { Authorization: `Bearer ${token}` }),
        },
        body: JSON.stringify({ messages: history }),
      });

      if (!response.ok) {
        throw new Error(`Server error ${response.status}: ${await response.text()}`);
      }

      const reader  = response.body.getReader();
      const decoder = new TextDecoder();
      let   buffer  = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const payload = line.slice(6);
          if (payload === '[DONE]') break;

          let parsed;
          try { parsed = JSON.parse(payload); } catch { continue; }
          if (parsed.error) throw new Error(parsed.error);

          if (parsed.content) {
            setMessages(prev => {
              const copy = [...prev];
              copy[copy.length - 1] = {
                ...copy[copy.length - 1],
                content: copy[copy.length - 1].content + parsed.content,
              };
              return copy;
            });
          }
        }
      }
    } catch (err) {
      setError(err.message);
      setMessages(prev => prev.slice(0, -1));
    } finally {
      setStreaming(false);
    }
  }, [messages, streaming, acquireToken]);

  const clearChat = useCallback(() => {
    setMessages([]);
    setError(null);
  }, []);

  return (
    <div className="app">
      <header className="app-header">
        <div className="header-brand">
          <svg className="header-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
            <path d="M12 2L2 7l10 5 10-5-10-5z" />
            <path d="M2 17l10 5 10-5" />
            <path d="M2 12l10 5 10-5" />
          </svg>
          <span>AI Foundry Chat</span>
        </div>

        <div className="header-actions">
          {apiScope && isAuthenticated && (
            <span className="header-user">{accounts[0]?.name}</span>
          )}
          {messages.length > 0 && (
            <button className="btn-clear" onClick={clearChat}>
              New chat
            </button>
          )}
          {apiScope && isAuthenticated && (
            <button
              className="btn-signout"
              onClick={() => instance.logoutPopup({ account: accounts[0] })}
            >
              Sign out
            </button>
          )}
        </div>
      </header>

      <main className="app-main">
        <ChatWindow messages={messages} streaming={streaming} />

        {error && (
          <div className="error-banner" role="alert">
            <span>⚠ {error}</span>
            <button onClick={() => setError(null)} aria-label="Dismiss error">✕</button>
          </div>
        )}

        <InputBar onSend={sendMessage} disabled={streaming} />
      </main>
    </div>
  );
}
