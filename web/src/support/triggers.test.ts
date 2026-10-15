import {
  DEFAULT_LONG_PAUSE_SECONDS,
  TRIGGERS,
  longPauseThresholdMs,
  type TriggerId,
} from './triggers'

describe('trigger table', () => {
  it('maps exactly the three R9 triggers', () => {
    expect(Object.keys(TRIGGERS).sort()).toEqual(
      ['high-stress-intent', 'long-pause', 'upload-failure'].sort(),
    )
  })

  it.each<TriggerId>(['long-pause', 'upload-failure', 'high-stress-intent'])(
    'maps %s to committed supportive content',
    (id) => {
      const { heading, message } = TRIGGERS[id].content

      expect(heading.trim()).not.toBe('')
      expect(message.trim()).not.toBe('')
    },
  )

  it('gives each trigger its own content', () => {
    const headings = Object.values(TRIGGERS).map((t) => t.content.heading)

    expect(new Set(headings).size).toBe(headings.length)
  })
})

describe('long-pause threshold', () => {
  const original = process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS

  afterEach(() => {
    if (original === undefined) {
      delete process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS
    } else {
      process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS = original
    }
  })

  it('defaults to 45 seconds', () => {
    delete process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS

    expect(DEFAULT_LONG_PAUSE_SECONDS).toBe(45)
    expect(longPauseThresholdMs()).toBe(45_000)
  })

  it('is configurable with NEXT_PUBLIC_LONG_PAUSE_SECONDS', () => {
    process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS = '20'

    expect(longPauseThresholdMs()).toBe(20_000)
  })

  it.each(['', 'abc', '0', '-5'])(
    'falls back to the default for an invalid value (%p)',
    (value) => {
      process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS = value

      expect(longPauseThresholdMs()).toBe(45_000)
    },
  )
})
