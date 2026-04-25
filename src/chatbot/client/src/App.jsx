import { useState, useCallback } from 'react';
import ChatWindow from './components/ChatWindow.jsx';
import InputBar from './components/InputBar.jsx';

export default function App() {
  const [messages, setMessages]   = useState([]);
  const [streaming, setStreaming] = useState(false);
  const [error, setError]         = useState(null);

  const sendMessage = useCallback(async (text) => {
    if (!text.trim() || streaming) return;

    const userMsg = { role: 'user',      content: text, id: crypto.randomUUID() };
    const asstMsg = { role: 'assistant', content: '',   id: crypto.randomUUID() };

    // Snapshot the conversation BEFORE adding the new pair (used for the API call)
    const history = messages.map(({ role, content }) => ({ role, content }));
    history.push({ role: 'user', content: text });

    setMessages(prev => [...prev, userMsg, asstMsg]);
    setStreaming(true);
    setError(null);

    try {
      const response = await fetch('/api/chat', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ messages: history }),
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
        buffer = lines.pop(); // keep incomplete last line

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue;
          const payload = line.slice(6);
          if (payload === '[DONE]') break;

          const parsed = JSON.parse(payload);
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
      // Remove the empty assistant placeholder on failure
      setMessages(prev => prev.slice(0, -1));
    } finally {
      setStreaming(false);
    }
  }, [messages, streaming]);

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

        {messages.length > 0 && (
          <button className="btn-clear" onClick={clearChat}>
            New chat
          </button>
        )}
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
