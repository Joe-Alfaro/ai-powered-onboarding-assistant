import { setVisibility } from '@/test-utils/visibility'
import { createTriggerEngine, type TriggerEngine } from './triggerEngine'
import {
  DEFAULT_LONG_PAUSE_SECONDS,
  TRIGGERS,
  type TriggerId,
} from './triggers'

// R9: every entry in the committed trigger table states its threshold
// explicitly, in the unit that trigger counts, and the engine fires on exactly
// that threshold rather than on a hard-coded one.
const EXPECTED_UNITS: Record<TriggerId, string> = {
  'long-pause': 'seconds',
  'upload-failure': 'failures',
  'high-stress-intent': 'distress-classifications',
}

const DISTRESS = { reply: 'That sounds hard.', trigger: 'high-stress-intent' }

function reportFailures(engine: TriggerEngine, times: number) {
  Array.from({ length: times }).forEach(() =>
    engine.reportUpload({ ok: false, status: 422 }),
  )
}

function reportDistress(engine: TriggerEngine, times: number) {
  Array.from({ length: times }).forEach(() =>
    engine.reportChatResponse(DISTRESS),
  )
}

describe('trigger table thresholds (R9)', () => {
  it.each(Object.entries(EXPECTED_UNITS))(
    'gives %s an explicit positive threshold in %s',
    (id, unit) => {
      const { threshold } = TRIGGERS[id as TriggerId]

      expect(threshold.unit).toBe(unit)
      expect(Number.isFinite(threshold.value)).toBe(true)
      expect(threshold.value).toBeGreaterThan(0)
    },
  )

  it('counts upload failures and distress classifications in whole numbers', () => {
    expect(Number.isInteger(TRIGGERS['upload-failure'].threshold.value)).toBe(
      true,
    )
    expect(
      Number.isInteger(TRIGGERS['high-stress-intent'].threshold.value),
    ).toBe(true)
  })

  it('states the long-pause default in the table', () => {
    expect(TRIGGERS['long-pause'].threshold.value).toBe(
      DEFAULT_LONG_PAUSE_SECONDS,
    )
  })
})

describe('the engine uses the trigger table thresholds (R9)', () => {
  let engine: TriggerEngine

  beforeEach(() => {
    jest.useFakeTimers()
    setVisibility('visible')
    delete process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS
  })

  afterEach(() => {
    engine?.stop()
    jest.restoreAllMocks()
    jest.useRealTimers()
  })

  describe('with the committed values', () => {
    it('fires upload-failure on the table count of failures, not before', () => {
      const count = TRIGGERS['upload-failure'].threshold.value
      engine = createTriggerEngine()

      reportFailures(engine, count - 1)
      expect(engine.active()).not.toContain('upload-failure')

      reportFailures(engine, 1)
      expect(engine.active()).toContain('upload-failure')
    })

    it('fires high-stress-intent on the table count of distress classifications, not before', () => {
      const count = TRIGGERS['high-stress-intent'].threshold.value
      engine = createTriggerEngine()

      reportDistress(engine, count - 1)
      expect(engine.active()).not.toContain('high-stress-intent')

      reportDistress(engine, 1)
      expect(engine.active()).toContain('high-stress-intent')
    })

    it('fires long-pause after the table number of seconds', () => {
      const seconds = TRIGGERS['long-pause'].threshold.value
      engine = createTriggerEngine()
      engine.start()

      jest.advanceTimersByTime(seconds * 1_000 - 1)
      expect(engine.active()).not.toContain('long-pause')

      jest.advanceTimersByTime(1)
      expect(engine.active()).toContain('long-pause')
    })
  })

  describe('with a non-default value in the table', () => {
    it('fires upload-failure only on the third failure when the table says 3', () => {
      jest.replaceProperty(TRIGGERS['upload-failure'], 'threshold', {
        unit: 'failures',
        value: 3,
      })
      engine = createTriggerEngine()

      reportFailures(engine, 2)
      expect(engine.active()).toEqual([])

      reportFailures(engine, 1)
      expect(engine.active()).toEqual(['upload-failure'])
    })

    it('fires high-stress-intent only on the second distress classification when the table says 2', () => {
      jest.replaceProperty(TRIGGERS['high-stress-intent'], 'threshold', {
        unit: 'distress-classifications',
        value: 2,
      })
      engine = createTriggerEngine()

      reportDistress(engine, 1)
      expect(engine.active()).toEqual([])

      reportDistress(engine, 1)
      expect(engine.active()).toEqual(['high-stress-intent'])
    })

    it('fires long-pause after the table seconds when the table says 12', () => {
      jest.replaceProperty(TRIGGERS['long-pause'], 'threshold', {
        unit: 'seconds',
        value: 12,
      })
      engine = createTriggerEngine()
      engine.start()

      jest.advanceTimersByTime(11_999)
      expect(engine.active()).toEqual([])

      jest.advanceTimersByTime(1)
      expect(engine.active()).toEqual(['long-pause'])
    })
  })

  describe('with thresholds passed to the engine', () => {
    it('respects non-default counts for every trigger', () => {
      engine = createTriggerEngine({
        thresholds: {
          'long-pause': 5,
          'upload-failure': 2,
          'high-stress-intent': 3,
        },
      })
      engine.start()

      reportFailures(engine, 1)
      reportDistress(engine, 2)
      jest.advanceTimersByTime(4_999)
      expect(engine.active()).toEqual([])

      reportFailures(engine, 1)
      expect(engine.active()).toEqual(['upload-failure'])

      reportDistress(engine, 1)
      expect(engine.active()).toEqual(['upload-failure', 'high-stress-intent'])
    })

    it('fires long-pause after the given number of seconds', () => {
      engine = createTriggerEngine({ thresholds: { 'long-pause': 5 } })
      engine.start()

      jest.advanceTimersByTime(4_999)
      expect(engine.active()).toEqual([])

      jest.advanceTimersByTime(1)
      expect(engine.active()).toEqual(['long-pause'])
    })
  })
})
