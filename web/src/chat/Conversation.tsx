export interface Turn {
  id: number
  speaker: 'You' | 'Assistant'
  text: string
}

interface ConversationProps {
  turns: readonly Turn[]
}

// A log region, polite by default, so new replies are announced. Each turn
// names its speaker in text, not by color or alignment alone (R34).
export function Conversation({ turns }: ConversationProps) {
  return (
    <div role="log" aria-label="Conversation">
      <ol>
        {turns.map(({ id, speaker, text }) => (
          <li key={id}>
            <strong>{speaker}:</strong> <span>{text}</span>
          </li>
        ))}
      </ol>
    </div>
  )
}
