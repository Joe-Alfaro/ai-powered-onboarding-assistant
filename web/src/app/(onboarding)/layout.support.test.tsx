import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { DEFAULT_LONG_PAUSE_SECONDS, TRIGGERS } from '@/support/triggers'
import { installFetch, jsonResponse } from '@/test-utils/fetch'
import { routeApi, setUpFlow } from '@/test-utils/flow'
import { setVisibility } from '@/test-utils/visibility'
import ChatPage from './chat/page'
import OnboardingLayout from './layout'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const PAUSE_MS = DEFAULT_LONG_PAUSE_SECONDS * 1_000
const LONG_PAUSE = TRIGGERS['long-pause'].content.heading
const HIGH_STRESS = TRIGGERS['high-stress-intent'].content.heading

function advance(ms: number) {
  act(() => {
    jest.advanceTimersByTime(ms)
  })
}

function setupUser() {
  return userEvent.setup({ advanceTimers: jest.advanceTimersByTime })
}

// A stand-in step page with no trigger engine of its own, so any supportive
// content it shows comes from the shared layout.
async function renderStep(pathname: string) {
  setUpFlow({ pathname })
  render(
    <OnboardingLayout>
      <h1>Step page</h1>
      <label htmlFor="field">Field</label>
      <input id="field" type="text" />
      <button type="button">Next</button>
    </OnboardingLayout>,
  )
  await screen.findByRole('heading', { name: 'Step page' })
}

function supportiveHeadings() {
  return Object.values(TRIGGERS)
    .map(({ content }) => content.heading)
    .filter((heading) => screen.queryAllByText(heading).length > 0)
}

describe('supportive content on every onboarding step (R9)', () => {
  beforeEach(() => {
    jest.useFakeTimers()
    setVisibility('visible')
    installFetch()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it.each(['/identity', '/identity/manual', '/confirm', '/schedule', '/done'])(
    'long-pause shows its content after the threshold on %s, from the shared layout',
    async (pathname) => {
      await renderStep(pathname)

      advance(PAUSE_MS - 1_000)
      expect(screen.queryByText(LONG_PAUSE)).toBeNull()

      advance(2_000)
      expect(screen.getByRole('heading', { name: LONG_PAUSE })).toBeVisible()
      expect(
        screen
          .getByRole('heading', { name: LONG_PAUSE })
          .closest('[role="status"]'),
      ).not.toBeNull()
    },
  )

  it('the long-pause timer does not fire while the user keeps typing on a step', async () => {
    const user = setupUser()
    await renderStep('/identity')
    screen.getByLabelText('Field').focus()

    for (let i = 0; i < 6; i += 1) {
      advance(30_000)
      await user.keyboard('a')
    }

    expect(screen.queryByText(LONG_PAUSE)).toBeNull()
  })

  it('the long-pause timer does not fire while the tab is hidden', async () => {
    await renderStep('/schedule')

    setVisibility('hidden')
    advance(10 * 60_000)

    expect(screen.queryByText(LONG_PAUSE)).toBeNull()
  })

  it('with no trigger met, a step shows no supportive content', async () => {
    const user = setupUser()
    await renderStep('/schedule')

    for (let i = 0; i < 6; i += 1) {
      advance(30_000)
      await user.click(screen.getByRole('button', { name: 'Next' }))
    }

    expect(supportiveHeadings()).toEqual([])
  })

  describe('on the chat step inside the layout', () => {
    async function renderChat() {
      setUpFlow({ pathname: '/chat' })
      render(
        <OnboardingLayout>
          <ChatPage />
        </OnboardingLayout>,
      )
      await screen.findByLabelText('Message')
    }

    it('shows the long-pause content once, not once per engine', async () => {
      await renderChat()

      advance(PAUSE_MS + 1_000)

      expect(screen.getAllByText(LONG_PAUSE)).toHaveLength(1)
    })

    it('shows high-stress content once when the API flags it, alongside long-pause', async () => {
      const user = setupUser()
      const fetchMock = installFetch()
      routeApi(fetchMock, {
        'POST /chat/messages': jsonResponse(200, {
          reply: 'That sounds hard. We will go one step at a time.',
          intent: 'express-distress',
          trigger: 'high-stress-intent',
          actions: [],
          assessment: null,
          scheduling: null,
        }),
      })
      await renderChat()

      await user.type(screen.getByLabelText('Message'), 'This is a lot')
      await user.click(screen.getByRole('button', { name: 'Send' }))
      expect(await screen.findByText(HIGH_STRESS)).toBeVisible()
      advance(PAUSE_MS + 1_000)

      expect(screen.getAllByText(HIGH_STRESS)).toHaveLength(1)
      expect(screen.getAllByText(LONG_PAUSE)).toHaveLength(1)
    })
  })
})
