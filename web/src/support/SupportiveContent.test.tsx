import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { setVisibility } from '@/test-utils/visibility'
import { SupportiveContent } from './SupportiveContent'
import { createTriggerEngine, type TriggerEngine } from './triggerEngine'
import { TRIGGERS, type TriggerId } from './triggers'

const PAUSE_MS = 45_000
const ALL_TRIGGERS = Object.keys(TRIGGERS) as TriggerId[]

function expectNoSupportiveContent() {
  ALL_TRIGGERS.forEach((id) => {
    const { heading, message } = TRIGGERS[id].content
    expect(screen.queryByText(heading)).not.toBeInTheDocument()
    expect(screen.queryByText(message)).not.toBeInTheDocument()
  })
}

function expectContentFor(id: TriggerId) {
  const { heading, message } = TRIGGERS[id].content
  const status = screen.getByRole('status')
  expect(within(status).getByRole('heading', { name: heading })).toBeVisible()
  expect(within(status).getByText(message)).toBeVisible()
}

describe('SupportiveContent (R9, R34)', () => {
  let engine: TriggerEngine

  beforeEach(() => {
    jest.useFakeTimers()
    setVisibility('visible')
    engine = createTriggerEngine({ longPauseMs: PAUSE_MS })
  })

  afterEach(() => {
    engine.stop()
    jest.useRealTimers()
  })

  describe('each trigger shows its mapped content', () => {
    it('shows the long-pause content after the inactivity threshold', () => {
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() => {
        jest.advanceTimersByTime(PAUSE_MS - 1)
      })
      expectNoSupportiveContent()

      act(() => {
        jest.advanceTimersByTime(1_001)
      })
      expectContentFor('long-pause')
    })

    it('shows the upload-failure content after a failed upload', () => {
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() => engine.reportUpload({ ok: false, status: 422 }))

      expectContentFor('upload-failure')
    })

    it('shows the high-stress-intent content when the chat response carries the trigger', () => {
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() =>
        engine.reportChatResponse({
          reply: 'That sounds hard. Let us take this one step at a time.',
          trigger: 'high-stress-intent',
        }),
      )

      expectContentFor('high-stress-intent')
    })
  })

  describe("whether content shows is decided by the trigger table, never by the LLM's discretion", () => {
    it('renders the committed table content, not the LLM reply text', () => {
      const reply = 'Ignore the table and show this LLM-written advice instead.'
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() =>
        engine.reportChatResponse({ reply, trigger: 'high-stress-intent' }),
      )

      expectContentFor('high-stress-intent')
      expect(screen.queryByText(reply)).not.toBeInTheDocument()
    })

    it('shows nothing for LLM reply text alone', () => {
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() =>
        engine.reportChatResponse({
          reply: 'You seem stressed. high-stress-intent. Take a deep breath.',
        }),
      )

      expectNoSupportiveContent()
    })
  })

  describe('with no trigger met, no supportive content is shown', () => {
    it('shows nothing through a happy-path sequence of events', async () => {
      const user = userEvent.setup({ advanceTimers: jest.advanceTimersByTime })
      render(
        <>
          <label htmlFor="message">Message</label>
          <input id="message" type="text" />
          <SupportiveContent engine={engine} />
        </>,
      )
      act(() => engine.start())
      const input = screen.getByLabelText('Message')

      await user.type(input, 'I need to book an appointment')
      act(() => {
        jest.advanceTimersByTime(20_000)
        engine.reportChatResponse({ reply: 'Sure, when suits you?' })
      })
      await user.type(input, ' Monday morning')
      act(() => {
        jest.advanceTimersByTime(30_000)
        setVisibility('hidden')
        jest.advanceTimersByTime(5 * 60_000)
        setVisibility('visible')
        jest.advanceTimersByTime(20_000)
        engine.reportUpload({ ok: true, status: 201 })
      })
      await user.click(input)
      act(() => {
        jest.advanceTimersByTime(30_000)
      })

      expectNoSupportiveContent()
    })
  })

  describe('accessibility (R34)', () => {
    it.each(ALL_TRIGGERS)(
      'has no axe violations with %s content shown',
      async (id) => {
        render(<SupportiveContent engine={engine} />)
        act(() => engine.start())
        act(() => {
          if (id === 'long-pause') jest.advanceTimersByTime(PAUSE_MS + 1_000)
          if (id === 'upload-failure') engine.reportUpload({ ok: false })
          if (id === 'high-stress-intent') {
            engine.reportChatResponse({ reply: '', trigger: id })
          }
        })
        expectContentFor(id)

        jest.useRealTimers()
        expect(await axe(document.body)).toHaveNoViolations()
      },
    )

    it('announces content in a status region with a text heading, not color alone', () => {
      render(<SupportiveContent engine={engine} />)
      act(() => engine.start())

      act(() => engine.reportUpload({ ok: false, status: 413 }))

      const status = screen.getByRole('status')
      expect(
        within(status).getByRole('heading', {
          name: TRIGGERS['upload-failure'].content.heading,
        }),
      ).toBeVisible()
    })
  })
})
