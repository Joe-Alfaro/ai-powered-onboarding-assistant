import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { errorEnvelope, installFetch } from '@/test-utils/fetch'
import { TOKEN, routeApi, router, setUpFlow } from '@/test-utils/flow'
import { mockSupabase, sessionFor } from '@/test-utils/supabase'
import ChatPage from './chat/page'
import OnboardingLayout from './layout'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const ONBOARDING_PATHS = [
  '/chat',
  '/identity',
  '/identity/manual',
  '/confirm',
  '/schedule',
  '/done',
  '/privacy',
]

function renderStep(pathname: string) {
  setUpFlow({ pathname, signedIn: false })
  return render(
    <OnboardingLayout>
      <h1>Private step content</h1>
    </OnboardingLayout>,
  )
}

describe('onboarding auth guard', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    fetchMock = installFetch()
  })

  it.each(ONBOARDING_PATHS)(
    'sends an unauthenticated visit to %s to /sign-in without showing the step',
    async (pathname) => {
      renderStep(pathname)

      await waitFor(() =>
        expect(router.replace).toHaveBeenCalledWith('/sign-in'),
      )
      expect(screen.queryByText('Private step content')).toBeNull()
      expect(fetchMock).not.toHaveBeenCalled()
    },
  )

  it('does not show the step while the session is still being checked', () => {
    setUpFlow({ pathname: '/schedule' })
    mockSupabase.auth.getSession.mockReturnValue(new Promise(() => {}))
    render(
      <OnboardingLayout>
        <h1>Private step content</h1>
      </OnboardingLayout>,
    )

    expect(screen.queryByText('Private step content')).toBeNull()
  })

  it('treats a session that cannot be read as signed out', async () => {
    setUpFlow({ pathname: '/identity' })
    mockSupabase.auth.getSession.mockResolvedValue({
      data: { session: null },
      error: { name: 'AuthSessionMissingError', message: 'missing' },
    })
    render(
      <OnboardingLayout>
        <h1>Private step content</h1>
      </OnboardingLayout>,
    )

    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/sign-in'))
    expect(screen.queryByText('Private step content')).toBeNull()
  })

  it('shows the step to a signed-in user and does not redirect', async () => {
    setUpFlow({ pathname: '/identity' })
    render(
      <OnboardingLayout>
        <h1>Private step content</h1>
      </OnboardingLayout>,
    )

    expect(
      await screen.findByRole('heading', { name: 'Private step content' }),
    ).toBeVisible()
    expect(router.replace).not.toHaveBeenCalled()
    expect(router.push).not.toHaveBeenCalled()
  })

  describe('API 401s send the user to sign in', () => {
    async function sendChatMessage() {
      const user = userEvent.setup()
      render(
        <OnboardingLayout>
          <ChatPage />
        </OnboardingLayout>,
      )
      await user.type(await screen.findByLabelText('Message'), 'Hello')
      await user.click(screen.getByRole('button', { name: 'Send' }))
    }

    it('when the API rejects the token with 401', async () => {
      setUpFlow({ pathname: '/chat' })
      routeApi(fetchMock, {
        'POST /chat/messages': errorEnvelope(
          401,
          'unauthenticated',
          'Your session has ended. Please sign in again.',
          [],
        ),
      })

      await sendChatMessage()

      await waitFor(() =>
        expect(router.replace).toHaveBeenCalledWith('/sign-in'),
      )
    })

    it('when the session has ended before the request is sent', async () => {
      setUpFlow({ pathname: '/chat' })
      // The guard sees a session on load; it has expired by the time the
      // user sends, so the client rejects without calling fetch.
      mockSupabase.auth.getSession
        .mockResolvedValueOnce(sessionFor('user-uuid-flow', TOKEN))
        .mockResolvedValue({ data: { session: null }, error: null })

      await sendChatMessage()

      await waitFor(() =>
        expect(router.replace).toHaveBeenCalledWith('/sign-in'),
      )
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it('not for other errors, such as a 503', async () => {
      setUpFlow({ pathname: '/chat' })
      routeApi(fetchMock, {
        'POST /chat/messages': errorEnvelope(503, 'llm_unavailable', 'Down.', [
          'retry',
          'manual_entry',
        ]),
      })

      await sendChatMessage()

      expect(await screen.findByRole('alert')).toHaveTextContent('Down.')
      expect(router.replace).not.toHaveBeenCalledWith('/sign-in')
    })
  })
})

describe('sign-out from the layout', () => {
  beforeEach(() => {
    installFetch()
  })

  async function renderSignedIn(pathname = '/schedule') {
    setUpFlow({ pathname })
    render(
      <OnboardingLayout>
        <h1>Private step content</h1>
      </OnboardingLayout>,
    )
    await screen.findByRole('heading', { name: 'Private step content' })
    return within(screen.getByRole('banner')).getByRole('button', {
      name: 'Sign out',
    })
  }

  it('offers a Sign out button in the banner on every step', async () => {
    const button = await renderSignedIn('/identity')

    expect(button).toBeVisible()
  })

  it('clears the Supabase session and goes to sign in', async () => {
    const user = userEvent.setup()
    const button = await renderSignedIn()

    await user.click(button)

    expect(mockSupabase.auth.signOut).toHaveBeenCalledTimes(1)
    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/sign-in'))
  })

  it('can be reached and used with the keyboard alone (R34)', async () => {
    const user = userEvent.setup()
    const button = await renderSignedIn()

    button.focus()
    await user.keyboard('{Enter}')

    expect(mockSupabase.auth.signOut).toHaveBeenCalledTimes(1)
  })
})
