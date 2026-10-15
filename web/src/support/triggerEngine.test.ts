import userEvent from '@testing-library/user-event'
import { screen } from '@testing-library/react'
import { setVisibility } from '@/test-utils/visibility'
import { createTriggerEngine, type TriggerEngine } from './triggerEngine'

const PAUSE_MS = 45_000

function renderStep() {
  document.body.innerHTML = `
    <form>
      <label for="message">Message</label>
      <input id="message" type="text" />
      <button type="button">Next</button>
    </form>
  `
}

async function repeat(times: number, step: () => Promise<void>) {
  await Array.from({ length: times }).reduce<Promise<void>>(
    (previous) => previous.then(step),
    Promise.resolve(),
  )
}

describe('trigger engine (R9)', () => {
  let engine: TriggerEngine

  beforeEach(() => {
    jest.useFakeTimers()
    setVisibility('visible')
    renderStep()
  })

  afterEach(() => {
    engine?.stop()
    jest.useRealTimers()
    document.body.innerHTML = ''
  })

  function setupUser() {
    return userEvent.setup({ advanceTimers: jest.advanceTimersByTime })
  }

  describe('each trigger shows its mapped content', () => {
    it('fires long-pause after the configured inactivity threshold on a step', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      jest.advanceTimersByTime(PAUSE_MS - 1)
      expect(engine.active()).not.toContain('long-pause')

      jest.advanceTimersByTime(1_001)
      expect(engine.active()).toEqual(['long-pause'])
    })

    it('uses the 45 second default when no threshold is given', () => {
      delete process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS
      engine = createTriggerEngine()
      engine.start()

      jest.advanceTimersByTime(44_999)
      expect(engine.active()).toEqual([])

      jest.advanceTimersByTime(1_001)
      expect(engine.active()).toEqual(['long-pause'])
    })

    it('uses NEXT_PUBLIC_LONG_PAUSE_SECONDS when set', () => {
      process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS = '10'
      try {
        engine = createTriggerEngine()
        engine.start()

        jest.advanceTimersByTime(9_999)
        expect(engine.active()).toEqual([])

        jest.advanceTimersByTime(1_001)
        expect(engine.active()).toEqual(['long-pause'])
      } finally {
        delete process.env.NEXT_PUBLIC_LONG_PAUSE_SECONDS
      }
    })

    it('fires upload-failure after a rejected upload response', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      engine.reportUpload({ ok: false, status: 422 })

      expect(engine.active()).toEqual(['upload-failure'])
    })

    it('fires upload-failure after a failed upload (no response)', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      engine.reportUpload({ ok: false })

      expect(engine.active()).toEqual(['upload-failure'])
    })

    it('does not fire upload-failure after a successful upload', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      engine.reportUpload({ ok: true, status: 201 })

      expect(engine.active()).toEqual([])
    })

    it('fires high-stress-intent when the chat response carries that trigger', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      engine.reportChatResponse({
        reply: 'That sounds hard. Let us take this one step at a time.',
        trigger: 'high-stress-intent',
      })

      expect(engine.active()).toEqual(['high-stress-intent'])
    })

    it('notifies subscribers when a trigger fires', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      const listener = jest.fn()
      const unsubscribe = engine.subscribe(listener)
      engine.start()

      engine.reportUpload({ ok: false, status: 500 })
      expect(listener).toHaveBeenCalled()

      listener.mockClear()
      unsubscribe()
      engine.reportChatResponse({ reply: 'ok', trigger: 'high-stress-intent' })
      expect(listener).not.toHaveBeenCalled()
    })
  })

  describe("the long-pause timer doesn't fire while the user is typing or the tab is hidden", () => {
    it('does not fire while the user keeps typing', async () => {
      const user = setupUser()
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()
      screen.getByLabelText('Message').focus()

      // Type a little every 30 s for 3 minutes, well past the threshold.
      // Keyboard only: no clicks or focus changes reset the timer here.
      await repeat(6, async () => {
        jest.advanceTimersByTime(30_000)
        await user.keyboard('a')
      })

      expect(engine.active()).toEqual([])

      jest.advanceTimersByTime(PAUSE_MS + 1_000)
      expect(engine.active()).toEqual(['long-pause'])
    })

    it('resets the timer on pointer activity', async () => {
      const user = setupUser()
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      jest.advanceTimersByTime(30_000)
      await user.click(screen.getByRole('button', { name: 'Next' }))
      jest.advanceTimersByTime(30_000)

      expect(engine.active()).toEqual([])
    })

    it('resets the timer on focus', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      jest.advanceTimersByTime(30_000)
      screen.getByLabelText('Message').focus()
      jest.advanceTimersByTime(30_000)

      expect(engine.active()).toEqual([])
    })

    it('does not fire while the tab is hidden', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      jest.advanceTimersByTime(10_000)
      setVisibility('hidden')
      jest.advanceTimersByTime(10 * 60_000)
      expect(engine.active()).toEqual([])

      setVisibility('visible')
      expect(engine.active()).toEqual([])

      jest.advanceTimersByTime(PAUSE_MS + 1_000)
      expect(engine.active()).toEqual(['long-pause'])
    })

    it('does not fire when started while the tab is hidden', () => {
      setVisibility('hidden')
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      jest.advanceTimersByTime(10 * 60_000)

      expect(engine.active()).toEqual([])
    })

    it('does not fire after the engine is stopped', () => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()
      engine.stop()

      jest.advanceTimersByTime(10 * 60_000)

      expect(engine.active()).toEqual([])
    })
  })

  describe("whether content shows is decided by the trigger table, never by the LLM's discretion", () => {
    it.each([
      'I can tell you are stressed. Here are some breathing tips.',
      'high-stress-intent',
      'trigger: "high-stress-intent"',
      '{"trigger":"upload-failure"}',
    ])('ignores LLM reply text alone: %p', (reply) => {
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()

      engine.reportChatResponse({ reply })
      engine.reportChatResponse({ reply, trigger: null })

      expect(engine.active()).toEqual([])
    })

    it.each([
      'long-pause',
      'upload-failure',
      'panic',
      'HIGH-STRESS-INTENT',
      '',
    ])(
      'ignores a chat trigger flag that is not high-stress-intent: %p',
      (trigger) => {
        engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
        engine.start()

        engine.reportChatResponse({ reply: 'Thanks.', trigger })

        expect(engine.active()).toEqual([])
      },
    )
  })

  describe('with no trigger met, no supportive content is shown', () => {
    it('drives a happy-path sequence and never activates a trigger', async () => {
      const user = setupUser()
      engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
      engine.start()
      const input = screen.getByLabelText('Message')

      // Chat about what they need.
      await user.type(input, 'I need to book my first appointment')
      jest.advanceTimersByTime(5_000)
      engine.reportChatResponse({
        reply: 'Sure. What kind of appointment are you looking for?',
        trigger: null,
      })
      jest.advanceTimersByTime(20_000)
      await user.clear(input)
      await user.type(input, 'A check-up, mornings work best')
      engine.reportChatResponse({
        reply: 'Got it, a morning check-up. Next, let us confirm your details.',
      })

      // Briefly switch tabs, then come back.
      jest.advanceTimersByTime(10_000)
      setVisibility('hidden')
      jest.advanceTimersByTime(2 * 60_000)
      setVisibility('visible')

      // Upload an ID photo successfully, confirm, and book.
      jest.advanceTimersByTime(15_000)
      await user.click(screen.getByRole('button', { name: 'Next' }))
      engine.reportUpload({ ok: true, status: 201 })
      jest.advanceTimersByTime(30_000)
      await user.click(screen.getByRole('button', { name: 'Next' }))
      jest.advanceTimersByTime(30_000)
      await user.click(screen.getByRole('button', { name: 'Next' }))
      engine.stop()
      jest.advanceTimersByTime(10 * 60_000)

      expect(engine.active()).toEqual([])
    })
  })
})
