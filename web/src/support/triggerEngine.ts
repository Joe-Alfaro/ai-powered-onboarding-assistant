import { longPauseThresholdMs, type TriggerId } from './triggers'

export interface TriggerEngineOptions {
  longPauseMs?: number
}

export interface UploadResult {
  ok: boolean
  status?: number
}

export interface ChatResponse {
  reply: string
  // Only the API's structured flag can fire content; the reply text is never
  // inspected.
  trigger?: string | null
}

export interface TriggerEngine {
  start(): void
  stop(): void
  reportUpload(result: UploadResult): void
  reportChatResponse(response: ChatResponse): void
  active(): readonly TriggerId[]
  subscribe(listener: () => void): () => void
}

// Input, focus and pointer events count as activity and restart the idle timer.
const ACTIVITY_EVENTS = ['keydown', 'input', 'focusin', 'pointerdown'] as const

export function createTriggerEngine({
  longPauseMs = longPauseThresholdMs(),
}: TriggerEngineOptions = {}): TriggerEngine {
  const listeners = new Set<() => void>()
  let activeTriggers: readonly TriggerId[] = []
  let pauseTimer: ReturnType<typeof setTimeout> | undefined
  let running = false

  function activate(id: TriggerId) {
    if (activeTriggers.includes(id)) return
    // A new array on each change keeps active() snapshot-stable for React.
    activeTriggers = [...activeTriggers, id]
    listeners.forEach((listener) => listener())
  }

  function clearPauseTimer() {
    clearTimeout(pauseTimer)
    pauseTimer = undefined
  }

  // Hidden tabs never count toward the pause. Returning to the tab restarts the
  // full threshold rather than resuming, so it can't fire on return.
  function restartPauseTimer() {
    clearPauseTimer()
    if (!running || document.visibilityState === 'hidden') return
    pauseTimer = setTimeout(() => activate('long-pause'), longPauseMs)
  }

  return {
    start() {
      if (running) return
      running = true
      ACTIVITY_EVENTS.forEach((type) =>
        document.addEventListener(type, restartPauseTimer, true),
      )
      document.addEventListener('visibilitychange', restartPauseTimer)
      restartPauseTimer()
    },

    stop() {
      running = false
      clearPauseTimer()
      ACTIVITY_EVENTS.forEach((type) =>
        document.removeEventListener(type, restartPauseTimer, true),
      )
      document.removeEventListener('visibilitychange', restartPauseTimer)
    },

    reportUpload({ ok }) {
      if (!ok) activate('upload-failure')
    },

    reportChatResponse({ trigger }) {
      if (trigger === 'high-stress-intent') activate('high-stress-intent')
    },

    active() {
      return activeTriggers
    },

    subscribe(listener) {
      listeners.add(listener)
      return () => {
        listeners.delete(listener)
      }
    },
  }
}
