'use client'

import { useSyncExternalStore } from 'react'
import type { TriggerEngine } from './triggerEngine'
import { TRIGGERS } from './triggers'

interface SupportiveContentProps {
  engine: TriggerEngine
}

// The status region is always rendered so screen readers announce content
// added to it later (R34).
export function SupportiveContent({ engine }: SupportiveContentProps) {
  const active = useSyncExternalStore(
    engine.subscribe,
    engine.active,
    engine.active,
  )

  return (
    <div role="status">
      {active.map((id) => {
        const { heading, message } = TRIGGERS[id].content
        return (
          <section key={id} aria-label={heading}>
            <h2>{heading}</h2>
            <p>{message}</p>
          </section>
        )
      })}
    </div>
  )
}
