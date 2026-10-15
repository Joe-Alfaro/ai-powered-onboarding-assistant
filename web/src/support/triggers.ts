// The committed trigger table (R9). Supportive content is shown only for an
// active trigger in this table, and its text comes only from here, never from
// LLM output.

export type TriggerId = 'long-pause' | 'upload-failure' | 'high-stress-intent'

export interface SupportiveCopy {
  heading: string
  message: string
}

export interface Trigger {
  content: SupportiveCopy
}

export const TRIGGERS: Record<TriggerId, Trigger> = {
  'long-pause': {
    content: {
      heading: 'Take your time',
      message:
        'There is no rush. Your answers are saved, so you can pause and pick up where you left off.',
    },
  },
  'upload-failure': {
    content: {
      heading: 'That upload did not go through',
      message:
        'This happens sometimes and is easy to fix. You can try another photo, or type your details in by hand instead.',
    },
  },
  'high-stress-intent': {
    content: {
      heading: 'You are not alone in this',
      message:
        'Starting something new can feel like a lot. We will go one step at a time, and you can stop whenever you need to.',
    },
  },
}

export const DEFAULT_LONG_PAUSE_SECONDS = 45

// Read at call time so tests and deployments can set it. An empty,
// non-numeric or non-positive value falls back to the default.
export function longPauseThresholdMs() {
  const seconds = Number(process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS)
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return DEFAULT_LONG_PAUSE_SECONDS * 1_000
  }
  return seconds * 1_000
}
