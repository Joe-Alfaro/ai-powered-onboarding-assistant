import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { errorEnvelope, headerOf, installFetch } from '@/test-utils/fetch'
import {
  ASSESSMENT,
  BOOKING,
  TOKEN,
  bookingsResponse,
  onboardingResponse,
  requestsMade,
  routeApi,
  setUpFlow,
  type OnboardingState,
} from '@/test-utils/flow'
import { formatLocalDateTime } from '@/time/formatLocalDateTime'
import DonePage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const CONFIRMED_BY_PHOTO: OnboardingState['identity'] = {
  confirmed: true,
  source: 'ocr',
  confirmed_at: '2026-11-01T14:05:00Z',
}

describe('done page', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    setUpFlow({ pathname: '/done' })
    fetchMock = installFetch()
  })

  function serve(
    state: OnboardingState = {},
    bookings: (typeof BOOKING)[] = [BOOKING],
  ) {
    routeApi(fetchMock, {
      'GET /onboarding': onboardingResponse({
        step: 'done',
        assessment: ASSESSMENT,
        identity: CONFIRMED_BY_PHOTO,
        ...state,
      }),
      'GET /bookings': bookingsResponse(bookings),
    })
  }

  it('reads the summary from the API with the session token', async () => {
    serve()
    render(<DonePage />)

    await screen.findByRole('region', { name: 'Your booking' })
    expect(requestsMade(fetchMock).sort()).toEqual([
      'GET /bookings',
      'GET /onboarding',
    ])
    fetchMock.mock.calls.forEach(([, init]) => {
      expect(headerOf(init, 'Authorization')).toBe(`Bearer ${TOKEN}`)
    })
  })

  it('has a level-one heading saying onboarding is complete', async () => {
    serve()
    render(<DonePage />)

    expect(
      await screen.findByRole('heading', { level: 1, name: /all set/i }),
    ).toBeVisible()
  })

  describe('completion summary', () => {
    it('shows the assessment summary from the API', async () => {
      serve()
      render(<DonePage />)

      const summary = await screen.findByRole('region', {
        name: 'Assessment summary',
      })
      expect(summary).toHaveTextContent(ASSESSMENT.reason)
      expect(summary).toHaveTextContent(ASSESSMENT.urgency)
      expect(summary).toHaveTextContent(ASSESSMENT.preferred_window)
      expect(summary).toHaveTextContent(ASSESSMENT.notes)
    })

    it('says the identity was confirmed from the ID photo', async () => {
      serve()
      render(<DonePage />)

      const identity = await screen.findByRole('region', {
        name: 'Your details',
      })
      expect(identity).toHaveTextContent(/confirmed/i)
      expect(identity).toHaveTextContent(/photo/i)
    })

    it('says the identity was confirmed from details entered by hand', async () => {
      serve({
        identity: { ...CONFIRMED_BY_PHOTO, source: 'manual' },
      })
      render(<DonePage />)

      const identity = await screen.findByRole('region', {
        name: 'Your details',
      })
      expect(identity).toHaveTextContent(/confirmed/i)
      expect(identity).toHaveTextContent(/entered|by hand|manual/i)
      expect(identity).not.toHaveTextContent(/photo/i)
    })

    it('says plainly when the identity is not confirmed, with a link back to that step', async () => {
      serve({
        identity: { confirmed: false, source: null, confirmed_at: null },
      })
      render(<DonePage />)

      const identity = await screen.findByRole('region', {
        name: 'Your details',
      })
      expect(identity).toHaveTextContent(/not (yet )?confirmed/i)
      expect(within(identity).getByRole('link')).toHaveAttribute(
        'href',
        '/identity',
      )
    })

    it('shows the booked time in the local zone with a zone label (R37)', async () => {
      serve()
      render(<DonePage />)

      const booking = await screen.findByRole('region', {
        name: 'Your booking',
      })
      // 15:00 UTC is 10:00 AM in New York, where the tests run.
      expect(booking).toHaveTextContent(
        formatLocalDateTime(BOOKING.slot.starts_at),
      )
      expect(booking).toHaveTextContent(/10:00\s*AM/)
      expect(booking).toHaveTextContent(/\bEST\b/)
      expect(booking).not.toHaveTextContent(/3:00\s*PM|15:00/)
      expect(booking).not.toHaveTextContent(BOOKING.slot.starts_at)
    })

    it('says when no call is booked, with a link to the schedule step', async () => {
      serve({}, [])
      render(<DonePage />)

      const booking = await screen.findByRole('region', {
        name: 'Your booking',
      })
      expect(booking).toHaveTextContent(/no call booked/i)
      expect(within(booking).getByRole('link')).toHaveAttribute(
        'href',
        '/schedule',
      )
    })

    it('says when the assessment is not saved, with a link to the chat step', async () => {
      serve({ assessment: null })
      render(<DonePage />)

      await screen.findByRole('region', { name: 'Your booking' })
      expect(
        screen.queryByRole('region', { name: 'Assessment summary' }),
      ).toBeNull()
      expect(
        screen.getByText(/assessment (is )?not (yet )?(saved|complete)/i),
      ).toBeVisible()
      expect(
        screen.getByRole('link', { name: /chat|assessment/i }),
      ).toHaveAttribute('href', '/chat')
    })
  })

  it('shows a clear error with a retry when the summary cannot be loaded (R30)', async () => {
    const user = userEvent.setup()
    let calls = 0
    routeApi(fetchMock, {
      'GET /onboarding': () => {
        calls += 1
        return calls === 1
          ? errorEnvelope(503, 'unavailable', 'The service is down.', ['retry'])
          : onboardingResponse({
              step: 'done',
              assessment: ASSESSMENT,
              identity: CONFIRMED_BY_PHOTO,
            })
      },
      'GET /bookings': bookingsResponse([BOOKING]),
    })
    render(<DonePage />)

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'The service is down.',
    )

    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(
      await screen.findByRole('region', { name: 'Assessment summary' }),
    ).toBeVisible()
    await waitFor(() => expect(screen.queryByRole('alert')).toBeNull())
  })

  it('has no accessibility violations (R34)', async () => {
    serve()
    const { container } = render(<DonePage />)
    await screen.findByRole('region', { name: 'Your booking' })

    expect(await axe(container)).toHaveNoViolations()
  })
})
