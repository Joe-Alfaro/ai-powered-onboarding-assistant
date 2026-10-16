import { render, screen, waitFor } from '@testing-library/react'
import { axe } from 'jest-axe'
import { errorEnvelope, installFetch } from '@/test-utils/fetch'
import {
  onboardingResponse,
  requestsMade,
  routeApi,
  router,
  setUpFlow,
} from '@/test-utils/flow'
import Home from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

describe('home page', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    fetchMock = installFetch()
  })

  it('sends a signed-out visitor to sign in without calling the API', async () => {
    setUpFlow({ pathname: '/', signedIn: false })
    render(<Home />)

    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/sign-in'))
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it.each([
    ['chat', '/chat'],
    ['identity', '/identity'],
    ['schedule', '/schedule'],
    ['done', '/done'],
  ])(
    'sends a signed-in user to their current step (%s)',
    async (step, path) => {
      setUpFlow({ pathname: '/' })
      routeApi(fetchMock, { 'GET /onboarding': onboardingResponse({ step }) })
      render(<Home />)

      await waitFor(() => expect(router.replace).toHaveBeenCalledWith(path))
      expect(requestsMade(fetchMock)).toEqual(['GET /onboarding'])
    },
  )

  it('sends the user to sign in when the API rejects the session (401)', async () => {
    setUpFlow({ pathname: '/' })
    routeApi(fetchMock, {
      'GET /onboarding': errorEnvelope(
        401,
        'unauthorized',
        'Your session has ended.',
        [],
      ),
    })
    render(<Home />)

    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/sign-in'))
  })

  it('shows the app heading while it works out where to go', () => {
    setUpFlow({ pathname: '/' })
    routeApi(fetchMock, { 'GET /onboarding': onboardingResponse() })
    render(<Home />)

    expect(
      screen.getByRole('heading', { name: 'Onboarding assistant' }),
    ).toBeInTheDocument()
  })

  it('has no accessibility violations (R34)', async () => {
    setUpFlow({ pathname: '/', signedIn: false })
    const { container } = render(<Home />)

    expect(await axe(container)).toHaveNoViolations()
    await waitFor(() => expect(router.replace).toHaveBeenCalled())
  })
})
