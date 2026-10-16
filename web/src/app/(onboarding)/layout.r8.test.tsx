import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { usePathname } from 'next/navigation'
import { installFetch } from '@/test-utils/fetch'
import {
  BOOKING,
  TOKEN,
  bookingsResponse,
  onboardingResponse,
  routeApi,
  router,
  setSignedIn,
  setUpFlow,
} from '@/test-utils/flow'
import { mockSupabase, sessionFor } from '@/test-utils/supabase'
import { formatLocalDateTime } from '@/time/formatLocalDateTime'
import SignInPage from '../sign-in/page'
import DonePage from './done/page'
import OnboardingLayout from './layout'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

// The web half of R8: nothing about the booking is kept in the browser, so
// after signing out and back in it comes from the API again. Playwright
// covers the same flow across real browser sessions.
describe('signing out and back in keeps the booking (R8)', () => {
  it('shows the booking from the API after sign-out then sign-in', async () => {
    const user = userEvent.setup()
    const fetchMock = installFetch()
    routeApi(fetchMock, {
      'GET /onboarding': onboardingResponse({ step: 'done' }),
      'GET /bookings': bookingsResponse([BOOKING]),
    })

    // Signed in on the done step: sign out from the banner.
    setUpFlow({ pathname: '/done' })
    const first = render(
      <OnboardingLayout>
        <DonePage />
      </OnboardingLayout>,
    )
    const banner = await screen.findByRole('banner')
    await user.click(within(banner).getByRole('button', { name: 'Sign out' }))
    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/sign-in'))
    first.unmount()
    expect(window.localStorage.length).toBe(0)
    expect(window.sessionStorage.length).toBe(0)

    // Sign in again on the sign-in page.
    router.replace.mockReset()
    jest.mocked(usePathname).mockReturnValue('/sign-in')
    mockSupabase.auth.signInWithPassword.mockImplementation(async () => {
      setSignedIn(true)
      return sessionFor('user-uuid-flow', TOKEN)
    })
    const second = render(<SignInPage />)
    await user.type(screen.getByLabelText('Email'), 'demo@example.test')
    await user.type(screen.getByLabelText('Password'), 'correct-horse')
    await user.click(screen.getByRole('button', { name: 'Sign in' }))
    await waitFor(() => expect(router.replace).toHaveBeenCalledWith('/done'))
    second.unmount()

    // The done step shows the same booking, read again from the API.
    jest.mocked(usePathname).mockReturnValue('/done')
    render(
      <OnboardingLayout>
        <DonePage />
      </OnboardingLayout>,
    )
    const booking = await screen.findByRole('region', { name: 'Your booking' })
    expect(booking).toHaveTextContent(
      formatLocalDateTime(BOOKING.slot.starts_at),
    )
  })
})
