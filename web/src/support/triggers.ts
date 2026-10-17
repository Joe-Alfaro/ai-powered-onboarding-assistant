// The committed trigger table (R9). Supportive content is shown only for an
// active trigger in this table, and its text comes only from here, never from
// LLM output.

export type TriggerId = 'long-pause' | 'upload-failure' | 'high-stress-intent'

export interface SupportiveCopy {
  heading: string
  message: string
}

// How much of what a trigger counts makes it fire, in that trigger's unit.
export interface Threshold {
  value: number
  unit: 'seconds' | 'failures' | 'distress-classifications'
}

export interface Trigger {
  threshold: Threshold
  content: SupportiveCopy
}

export const DEFAULT_LONG_PAUSE_SECONDS = 45

export const TRIGGERS: Record<TriggerId, Trigger> = {
  'long-pause': {
    // Seconds of no activity on a visible tab. NEXT_PUBLIC_LONG_PAUSE_SECONDS
    // overrides it.
    threshold: { value: DEFAULT_LONG_PAUSE_SECONDS, unit: 'seconds' },
    content: {
      heading: 'Take your time',
      message:
        'There is no rush. Your answers are saved, so you can pause and pick up where you left off.',
    },
  },
  'upload-failure': {
    threshold: { value: 1, unit: 'failures' },
    content: {
      heading: 'That upload did not go through',
      message:
        'This happens sometimes and is easy to fix. You can try another photo, or type your details in by hand instead.',
    },
  },
  'high-stress-intent': {
    // Chat replies the API flagged as high-stress intent.
    threshold: { value: 1, unit: 'distress-classifications' },
    content: {
      heading: 'You are not alone in this',
      message:
        'Starting something new can feel like a lot. We will go one step at a time, and you can stop whenever you need to.',
    },
  },
}

// Read at call time so tests and deployments can set it. An empty,
// non-numeric or non-positive value falls back to the table's value.
export function longPauseThresholdMs() {
  const seconds = Number(process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS)
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return TRIGGERS['long-pause'].threshold.value * 1_000
  }
  return seconds * 1_000
}
