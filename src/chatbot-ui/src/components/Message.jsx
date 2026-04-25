const UserIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8v2.4h19.2v-2.4c0-3.2-6.4-4.8-9.6-4.8z" />
  </svg>
);

const BotIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7H3a7 7 0 0 1 7-7h1V5.73A2 2 0 0 1 10 4a2 2 0 0 1 2-2M7.5 13A1.5 1.5 0 0 0 6 14.5 1.5 1.5 0 0 0 7.5 16 1.5 1.5 0 0 0 9 14.5 1.5 1.5 0 0 0 7.5 13m9 0A1.5 1.5 0 0 0 15 14.5 1.5 1.5 0 0 0 16.5 16 1.5 1.5 0 0 0 18 14.5 1.5 1.5 0 0 0 16.5 13M5 18v1a1 1 0 0 0 1 1h1v2h2v-2h6v2h2v-2h1a1 1 0 0 0 1-1v-1H5z" />
  </svg>
);

const TypingIndicator = () => (
  <span className="typing-dots" aria-label="AI is thinking">
    <span /><span /><span />
  </span>
);

export default function Message({ message, isStreaming }) {
  const isUser = message.role === 'user';
  const showTyping = isStreaming && message.content === '';

  return (
    <div className={`message ${isUser ? 'message-user' : 'message-assistant'}`}>
      <div className="message-avatar" aria-hidden="true">
        {isUser ? <UserIcon /> : <BotIcon />}
      </div>

      <div className="message-bubble">
        {showTyping ? (
          <TypingIndicator />
        ) : (
          <p className="message-content">
            {message.content}
            {isStreaming && <span className="cursor" aria-hidden="true">▊</span>}
          </p>
        )}
      </div>
    </div>
  );
}
