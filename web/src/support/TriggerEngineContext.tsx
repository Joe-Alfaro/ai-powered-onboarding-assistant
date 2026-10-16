'use client'

import { createContext, useContext, useEffect, useState } from 'react'
import { createTriggerEngine, type TriggerEngine } from './triggerEngine'

// The onboarding layout owns one trigger engine per step and shows its
// content, so long-pause fires on every step (R9). Pages report uploads and
// chat replies to that same engine, so each trigger's content shows once.
export const TriggerEngineContext = createContext<TriggerEngine | null>(null)

// The layout's engine when there is one. A page rendered on its own (as in its
// own tests) runs its own engine and must show its content itself.
export function useStepTriggerEngine() {
  const shared = useContext(TriggerEngineContext)
  const [own] = useState(() => createTriggerEngine())

  useEffect(() => {
    if (shared) return
    own.start()
    return () => own.stop()
  }, [own, shared])

  return { engine: shared ?? own, ownsEngine: shared === null }
}
