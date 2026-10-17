import { createClient } from '@supabase/supabase-js'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { fakeSchedulingApi, slotAt } from '@/test-utils/schedulingApi'
import {
  mockSupabase,
  resetMockSupabase,
  sessionFor,
} from '@/test-utils/supabase'
import SchedulePage from './page'

jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const MON_9AM = slotAt('slot-mon', '2030-03-04T14:00:00Z')
const MON_9AM_TEXT = /Mon, Mar 4, 2030, 9:00\sAM\sEST/

describe('schedule page', () => {
  beforeAll(() => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
    process.env.NEXT_PUBLIC_API_URL = 'https://api.example.test'
  })

  beforeEach(() => {
    resetMockSupabase()
    jest
      .mocked(createClient)
      .mockReturnValue(
        mockSupabase as unknown as ReturnType<typeof createClient>,
      )
    mockSupabase.auth.getSession.mockResolvedValue(
      sessionFor('user-uuid-1', 'token-from-supabase'),
    )
  })

  it('R6: shows a heading and the open slots from the API, signed in with the session token', async () => {
    const api = fakeSchedulingApi({ slots: [MON_9AM] })

    render(<SchedulePage />)

    expect(
      screen.getByRole('heading', { level: 1, name: 'Schedule a call' }),
    ).toBeInTheDocument()
    expect(
      await screen.findByRole('radio', { name: MON_9AM_TEXT }),
    ).toBeInTheDocument()
    expect(api.fetchMock).toHaveBeenCalledWith(
      'https://api.example.test/slots',
      expect.anything(),
    )
    expect(api.requestsTo('GET', '/slots')[0].authorization).toBe(
      'Bearer token-from-supabase',
    )
  })

  it('R8: a new session sees the booking held by the API', async () => {
    mockSupabase.auth.getSession.mockResolvedValue(
      sessionFor('user-uuid-1', 'token-from-a-new-browser'),
    )
    const api = fakeSchedulingApi({
      slots: [MON_9AM],
      booking: { id: 'booking-1', slotId: MON_9AM.id },
    })

    render(<SchedulePage />)

    expect(
      await screen.findByRole('region', { name: 'Your booking' }),
    ).toHaveTextContent(MON_9AM_TEXT)
    expect(api.requestsTo('GET', '/bookings')[0].authorization).toBe(
      'Bearer token-from-a-new-browser',
    )
  })

  it('R34: offers no way on until a call is booked', async () => {
    fakeSchedulingApi({ slots: [MON_9AM] })

    render(<SchedulePage />)
    await screen.findByRole('radio', { name: MON_9AM_TEXT })

    expect(
      screen.queryByRole('link', { name: /^continue/i }),
    ).not.toBeInTheDocument()
  })

  it('R34: once a call is booked, links on to the summary', async () => {
    const user = userEvent.setup()
    fakeSchedulingApi({ slots: [MON_9AM] })

    render(<SchedulePage />)
    await user.click(await screen.findByRole('radio', { name: MON_9AM_TEXT }))
    await user.click(screen.getByRole('button', { name: 'Book this time' }))

    expect(
      await screen.findByRole('link', { name: 'Continue to the summary' }),
    ).toHaveAttribute('href', '/done')
  })

  it('R34: hides the way on while the booking is being changed', async () => {
    const user = userEvent.setup()
    fakeSchedulingApi({
      slots: [MON_9AM],
      booking: { id: 'booking-1', slotId: MON_9AM.id },
    })

    render(<SchedulePage />)
    await screen.findByRole('link', { name: 'Continue to the summary' })
    await user.click(screen.getByRole('button', { name: 'Reschedule' }))

    expect(
      screen.queryByRole('link', { name: /^continue/i }),
    ).not.toBeInTheDocument()
  })

  it('R34: has no accessibility violations', async () => {
    fakeSchedulingApi({ slots: [MON_9AM] })
    const { container } = render(<SchedulePage />)
    await screen.findByRole('radio', { name: MON_9AM_TEXT })

    expect(await axe(container)).toHaveNoViolations()
  })
})
