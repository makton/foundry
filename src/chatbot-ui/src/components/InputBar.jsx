import { useState, useRef, useEffect } from 'react';

const SendIcon = () => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z" />
  </svg>
);

const LoadingIcon = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" className="spin" aria-hidden="true">
    <circle cx="12" cy="12" r="9" strokeOpacity=".25" />
    <path d="M21 12a9 9 0 0 0-9-9" strokeLinecap="round" />
  </svg>
);

export default function InputBar({ onSend, disabled }) {
  const [text, setText]   = useState('');
  const textareaRef       = useRef(null);

  // Auto-resize textarea up to 5 lines
  useEffect(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 140)}px`;
  }, [text]);

  const handleSend = () => {
    const trimmed = text.trim();
    if (!trimmed || disabled) return;
    onSend(trimmed);
    setText('');
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <div className="input-bar">
      <textarea
        ref={textareaRef}
        value={text}
        onChange={e => setText(e.target.value)}
        onKeyDown={handleKeyDown}
        placeholder="Message AI Foundry… (Enter to send, Shift+Enter for new line)"
        disabled={disabled}
        rows={1}
        className="input-textarea"
        aria-label="Chat message input"
        aria-multiline="true"
      />
      <button
        onClick={handleSend}
        disabled={disabled || !text.trim()}
        className="send-btn"
        aria-label={disabled ? 'AI is responding' : 'Send message'}
      >
        {disabled ? <LoadingIcon /> : <SendIcon />}
      </button>
    </div>
  );
}
