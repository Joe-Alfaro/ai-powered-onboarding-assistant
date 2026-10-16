import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { TRIGGERS } from '@/support/triggers'
import { errorEnvelope, headerOf, installFetch } from '@/test-utils/fetch'
import {
  TOKEN,
  onboardingResponse,
  requestsMade,
  routeApi,
  router,
  setSignedIn,
  setUpFlow,
} from '@/test-utils/flow'
import { mockSupabase, sessionFor } from '@/test-utils/supabase'
import SignInPage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const EMAIL = 'demo@example.test'
const PASSWORD = 'correct-horse-battery'

async function signIn(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Email'), EMAIL)
  await user.type(screen.getByLabelText('Password'), PASSWORD)
  await user.click(screen.getByRole('button', { name: 'Sign in' }))
}

describe('sign-in page', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    setUpFlow({ pathname: '/sign-in', signedIn: false })
    fetchMock = installFetch()
    // Signing in stores the session, so the API client finds a token after.
    mockSupabase.auth.signInWithPassword.mockImplementation(async () => {
      setSignedIn(true)
      return sessionFor('user-uuid-flow', TOKEN)
    })
  })

  it('shows a sign-in heading and the email and password form', () => {
    render(<SignInPage />)

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      /sign in/i,
    )
    expect(screen.getByLabelText('Email')).toBeVisible()
    expect(screen.getByLabelText('Password')).toBeVisible()
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeVisible()
  })

  it('asks for nothing from the API before the user signs in', () => {
    render(<SignInPage />)

    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([
    ['chat', '/chat'],
    ['identity', '/identity'],
    ['schedule', '/schedule'],
    ['done', '/done'],
  ])(
    "a successful sign-in goes to the user's current step (%s)",
    async (step, path) => {
      const user = userEvent.setup()
      routeApi(fetchMock, { 'GET /onboarding': onboardingResponse({ step }) })
      render(<SignInPage />)

      await signIn(user)

      await waitFor(() => expect(router.replace).toHaveBeenCalledWith(path))
      expect(requestsMade(fetchMock)).toEqual(['GET /onboarding'])
      expect(headerOf(fetchMock.mock.calls[0][1], 'Authorization')).toBe(
        `Bearer ${TOKEN}`,
      )
    },
  )

  it('starts at the chat step when the API reports a step it does not know', async () => {
    const user = userEvent.setup()
    routeApi(fetchMock, {
      'GET /onboarding': onboardingResponse({ step: 'something-new' }),
    })
    render(<SignInPage />)

    await signIn(user)

    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/chat'))
  })

  it('stays on the page with wrong credentials and asks the API nothing', async () => {
    const user = userEvent.setup()
    mockSupabase.auth.signInWithPassword.mockResolvedValue({
      data: { session: null, user: null },
      error: {
        name: 'AuthApiError',
        message: 'Invalid login credentials',
        status: 400,
      },
    })
    render(<SignInPage />)

    await signIn(user)

    expect(await screen.findByRole('alert')).toBeVisible()
    expect(router.replace).not.toHaveBeenCalled()
    expect(router.push).not.toHaveBeenCalled()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('shows a clear error with a retry when the current step cannot be loaded (R30)', async () => {
    const user = userEvent.setup()
    let calls = 0
    routeApi(fetchMock, {
      'GET /onboarding': () => {
        calls += 1
        return calls === 1
          ? errorEnvelope(503, 'unavailable', 'The service is down.', ['retry'])
          : onboardingResponse({ step: 'schedule' })
      },
    })
    render(<SignInPage />)

    await signIn(user)

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'The service is down.',
    )
    expect(router.replace).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: 'Try again' }))

    await waitFor(() =>
      expect(router.replace).toHaveBeenCalledWith('/schedule'),
    )
  })

  it('shows no supportive content (R9)', () => {
    render(<SignInPage />)

    Object.values(TRIGGERS).forEach(({ content }) => {
      expect(screen.queryByText(content.heading)).toBeNull()
    })
  })

  it('has no accessibility violations (R34)', async () => {
    const { container } = render(<SignInPage />)

    expect(await axe(container)).toHaveNoViolations()
  })
})
