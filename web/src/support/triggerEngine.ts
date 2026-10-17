import { longPauseThresholdMs, TRIGGERS, type TriggerId } from './triggers'

export interface TriggerEngineOptions {
  // Overrides the trigger table, each in that trigger's unit.
  thresholds?: Partial<Record<TriggerId, number>>
  // Overrides the long-pause threshold in milliseconds.
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
  thresholds = {},
  longPauseMs,
}: TriggerEngineOptions = {}): TriggerEngine {
  const pauseMs =
    longPauseMs ??
    (thresholds['long-pause'] === undefined
      ? longPauseThresholdMs()
      : thresholds['long-pause'] * 1_000)
  const uploadFailureLimit =
    thresholds['upload-failure'] ?? TRIGGERS['upload-failure'].threshold.value
  const distressLimit =
    thresholds['high-stress-intent'] ??
    TRIGGERS['high-stress-intent'].threshold.value
  const listeners = new Set<() => void>()
  let activeTriggers: readonly TriggerId[] = []
  let uploadFailures = 0
  let distressClassifications = 0
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
    pauseTimer = setTimeout(() => activate('long-pause'), pauseMs)
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
      if (ok) return
      uploadFailures += 1
      if (uploadFailures >= uploadFailureLimit) activate('upload-failure')
    },

    reportChatResponse({ trigger }) {
      if (trigger !== 'high-stress-intent') return
      distressClassifications += 1
      if (distressClassifications >= distressLimit) {
        activate('high-stress-intent')
      }
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
