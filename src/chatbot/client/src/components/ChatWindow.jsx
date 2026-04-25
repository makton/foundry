import { useEffect, useRef } from 'react';
import Message from './Message.jsx';

export default function ChatWindow({ messages, streaming }) {
  const bottomRef = useRef(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  if (messages.length === 0) {
    return (
      <div className="chat-window chat-empty">
        <div className="empty-state">
          <div className="empty-icon" aria-hidden="true">💬</div>
          <h2>How can I help you today?</h2>
          <p>Ask me anything about your documents and data sources.</p>
          <ul className="suggestion-list" aria-label="Suggestions">
            <li onClick={() => {}}>Summarise the latest uploaded documents</li>
            <li onClick={() => {}}>What topics are covered in my knowledge base?</li>
            <li onClick={() => {}}>Find relevant sections about a specific subject</li>
          </ul>
        </div>
      </div>
    );
  }

  return (
    <div className="chat-window" role="log" aria-live="polite" aria-label="Conversation">
      {messages.map((msg, idx) => (
        <Message
          key={msg.id}
          message={msg}
          isStreaming={streaming && idx === messages.length - 1 && msg.role === 'assistant'}
        />
      ))}
      <div ref={bottomRef} aria-hidden="true" />
    </div>
  );
}
