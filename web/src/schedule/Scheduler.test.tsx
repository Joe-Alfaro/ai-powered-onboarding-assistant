import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { createApiClient } from '@/api/client'
import { errorEnvelope } from '@/test-utils/fetch'
import { fakeSchedulingApi, slotAt } from '@/test-utils/schedulingApi'
import { Scheduler } from './Scheduler'

// Jest runs in America/New_York (jest.config.mjs), so these UTC instants must
// show as Eastern time with an EST or EDT label (R37).
const API_URL = 'https://api.example.test'

const MON_9AM = slotAt('slot-mon', '2030-03-04T14:00:00Z')
const TUE_1030AM = slotAt('slot-tue', '2030-03-05T15:30:00Z')
// 02:30 UTC on Mar 7 is still the evening of Mar 6 in New York.
const WED_930PM = slotAt('slot-wed', '2030-03-07T02:30:00Z')
// After the Mar 10 daylight-saving change, so the label is EDT.
const TUE_12_9AM = slotAt('slot-dst', '2030-03-12T13:00:00Z')

const MON_9AM_TEXT = /Mon, Mar 4, 2030, 9:00\sAM\sEST/
const TUE_1030AM_TEXT = /Tue, Mar 5, 2030, 10:30\sAM\sEST/
const WED_930PM_TEXT = /Wed, Mar 6, 2030, 9:30\sPM\sEST/
const TUE_12_9AM_TEXT = /Tue, Mar 12, 2030, 9:00\sAM\sEDT/

function apiFor(token: string) {
  return createApiClient({
    baseUrl: API_URL,
    getAccessToken: async () => token,
  })
}

function renderScheduler(token = 'token-a') {
  return render(<Scheduler api={apiFor(token)} />)
}

// The slot picker, whether it is built from native radios in a fieldset or
// from an ARIA radiogroup.
function slotPicker() {
  return (
    screen.queryByRole('radiogroup', { name: 'Available times' }) ??
    screen.getByRole('group', { name: 'Available times' })
  )
}

async function findSlot(name: RegExp) {
  return screen.findByRole('radio', { name })
}

function bookingRegion() {
  return screen.getByRole('region', { name: 'Your booking' })
}

async function findBookingRegion() {
  return screen.findByRole('region', { name: 'Your booking' })
}

// Presses Tab until the element is focused, the way a keyboard user would
// reach it. Fails if it is not reachable by Tab.
async function tabTo(
  user: ReturnType<typeof userEvent.setup>,
  target: () => HTMLElement,
) {
  const attempts = 40
  const reached = await Array.from({ length: attempts }).reduce<
    Promise<boolean>
  >(async (previous) => {
    if (await previous) return true
    if (document.activeElement === target()) return true
    await user.tab()
    return document.activeElement === target()
  }, Promise.resolve(false))
  expect(reached).toBe(true)
}

async function book(
  user: ReturnType<typeof userEvent.setup>,
  slotText: RegExp,
) {
  await user.click(await findSlot(slotText))
  await user.click(screen.getByRole('button', { name: 'Book this time' }))
}

describe('Scheduler', () => {
  beforeEach(() => {
    window.localStorage.clear()
    window.sessionStorage.clear()
  })

  describe('R6: viewing and booking a slot', () => {
    it('R6: a signed-in user sees open slots', async () => {
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })

      renderScheduler()

      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
      expect(await findSlot(TUE_1030AM_TEXT)).toBeInTheDocument()
      expect(within(slotPicker()).getAllByRole('radio')).toHaveLength(2)
      expect(api.requestsTo('GET', '/slots')[0].authorization).toBe(
        'Bearer token-a',
      )
    })

    it('R6: booking a slot shows a confirmation with its date and time', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()

      await book(user, TUE_1030AM_TEXT)

      const region = await findBookingRegion()
      expect(region).toHaveTextContent(TUE_1030AM_TEXT)
      expect(await screen.findByRole('status')).toHaveTextContent(/booked/i)
      expect(api.requestsTo('POST', '/bookings')).toEqual([
        expect.objectContaining({ body: { slot_id: TUE_1030AM.id } }),
      ])
    })

    it('R6: a booked slot no longer appears as open', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()

      await book(user, TUE_1030AM_TEXT)
      await findBookingRegion()

      expect(
        screen.queryByRole('radio', { name: TUE_1030AM_TEXT }),
      ).not.toBeInTheDocument()
      await user.click(screen.getByRole('button', { name: 'Reschedule' }))
      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
      expect(
        screen.queryByRole('radio', { name: TUE_1030AM_TEXT }),
      ).not.toBeInTheDocument()
    })

    it('says so when there are no open slots', async () => {
      fakeSchedulingApi({ slots: [] })

      renderScheduler()

      expect(await screen.findByText(/no open times/i)).toBeInTheDocument()
      expect(
        screen.queryByRole('button', { name: 'Book this time' }),
      ).not.toBeInTheDocument()
    })
  })

  describe('R7: a slot taken by someone else', () => {
    it('R7: a 409 shows that the slot was just taken and keeps the user on the picker', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()
      await findSlot(MON_9AM_TEXT)
      api.takeSlot(MON_9AM.id)

      await book(user, MON_9AM_TEXT)

      expect(await screen.findByRole('alert')).toHaveTextContent(/just taken/i)
      expect(
        screen.queryByRole('region', { name: 'Your booking' }),
      ).not.toBeInTheDocument()
      expect(slotPicker()).toBeInTheDocument()
      expect(
        screen.getByRole('button', { name: 'Book this time' }),
      ).toBeInTheDocument()
    })

    it('R7: the slots are refreshed, so the taken slot is gone and the rest remain', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()
      await findSlot(MON_9AM_TEXT)
      api.takeSlot(MON_9AM.id)

      await book(user, MON_9AM_TEXT)
      await screen.findByRole('alert')

      await waitFor(() =>
        expect(
          screen.queryByRole('radio', { name: MON_9AM_TEXT }),
        ).not.toBeInTheDocument(),
      )
      expect(screen.getByRole('radio', { name: TUE_1030AM_TEXT })).toBeVisible()
      expect(api.requestsTo('GET', '/slots').length).toBeGreaterThanOrEqual(2)
    })

    it('R7: a 409 on reschedule leaves the original booking in place and shown', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM, WED_930PM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      renderScheduler()
      await user.click(
        await screen.findByRole('button', { name: 'Reschedule' }),
      )
      await findSlot(TUE_1030AM_TEXT)
      api.takeSlot(TUE_1030AM.id)

      await user.click(screen.getByRole('radio', { name: TUE_1030AM_TEXT }))
      await user.click(
        screen.getByRole('button', { name: 'Move to this time' }),
      )

      expect(await screen.findByRole('alert')).toHaveTextContent(/just taken/i)
      expect(bookingRegion()).toHaveTextContent(MON_9AM_TEXT)
      await waitFor(() =>
        expect(
          screen.queryByRole('radio', { name: TUE_1030AM_TEXT }),
        ).not.toBeInTheDocument(),
      )
      expect(screen.getByRole('radio', { name: WED_930PM_TEXT })).toBeVisible()
      expect(api.activeBooking()?.slot.id).toBe(MON_9AM.id)
    })
  })

  describe('R8: the booking comes from the API', () => {
    it('R8: on load, an existing booking is fetched and shown', async () => {
      const api = fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM],
        booking: { id: 'booking-1', slotId: TUE_1030AM.id },
      })

      renderScheduler()

      const region = await findBookingRegion()
      expect(region).toHaveTextContent(TUE_1030AM_TEXT)
      expect(region).toHaveTextContent(/booked/i)
      expect(
        screen.queryByRole('button', { name: 'Book this time' }),
      ).not.toBeInTheDocument()
      expect(api.requestsTo('GET', '/bookings')).toHaveLength(1)
    })

    it('R8: a new session sees a booking made in an earlier one', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      const first = renderScheduler('token-first-session')
      await book(user, MON_9AM_TEXT)
      await findBookingRegion()
      first.unmount()
      window.localStorage.clear()
      window.sessionStorage.clear()

      renderScheduler('token-second-session')

      expect(await findBookingRegion()).toHaveTextContent(MON_9AM_TEXT)
      const [secondLoad] = api
        .requestsTo('GET', '/bookings')
        .filter(
          ({ authorization }) =>
            authorization === 'Bearer token-second-session',
        )
      expect(secondLoad).toBeDefined()
    })

    it('R8: keeps no booking in browser storage', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()

      await book(user, MON_9AM_TEXT)
      await findBookingRegion()

      expect(window.localStorage).toHaveLength(0)
      expect(window.sessionStorage).toHaveLength(0)
    })
  })

  describe('R36: rescheduling and cancelling', () => {
    it('R36: moves the booking to another open slot and shows the new time', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      renderScheduler()

      await user.click(
        await screen.findByRole('button', { name: 'Reschedule' }),
      )
      await user.click(await findSlot(TUE_1030AM_TEXT))
      await user.click(
        screen.getByRole('button', { name: 'Move to this time' }),
      )

      expect(await screen.findByRole('status')).toHaveTextContent(
        /rescheduled/i,
      )
      await waitFor(() =>
        expect(bookingRegion()).toHaveTextContent(TUE_1030AM_TEXT),
      )
      expect(bookingRegion()).not.toHaveTextContent(MON_9AM_TEXT)
      expect(api.requestsTo('PATCH', '/bookings/booking-1')).toEqual([
        expect.objectContaining({ body: { slot_id: TUE_1030AM.id } }),
      ])
    })

    it('R36: after a reschedule the old slot is open again', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      renderScheduler()
      await user.click(
        await screen.findByRole('button', { name: 'Reschedule' }),
      )
      await user.click(await findSlot(TUE_1030AM_TEXT))
      await user.click(
        screen.getByRole('button', { name: 'Move to this time' }),
      )
      await screen.findByRole('status')

      await user.click(screen.getByRole('button', { name: 'Reschedule' }))

      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
    })

    it('R36: cancelling asks for confirmation first, and keeping the booking sends nothing', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({
        slots: [MON_9AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      renderScheduler()

      await user.click(
        await screen.findByRole('button', { name: 'Cancel booking' }),
      )

      expect(screen.getByText(/cancel your call/i)).toBeInTheDocument()
      expect(api.requestsTo('DELETE', /^\/bookings\//)).toHaveLength(0)
      await user.click(screen.getByRole('button', { name: 'Keep my booking' }))
      expect(api.requestsTo('DELETE', /^\/bookings\//)).toHaveLength(0)
      expect(bookingRegion()).toHaveTextContent(MON_9AM_TEXT)
      expect(
        screen.queryByRole('button', { name: 'Yes, cancel it' }),
      ).not.toBeInTheDocument()
    })

    it('R36: confirming the cancellation cancels it and the slot is open again', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      renderScheduler()

      await user.click(
        await screen.findByRole('button', { name: 'Cancel booking' }),
      )
      await user.click(screen.getByRole('button', { name: 'Yes, cancel it' }))

      expect(await screen.findByRole('status')).toHaveTextContent(/cancelled/i)
      expect(api.requestsTo('DELETE', '/bookings/booking-1')).toHaveLength(1)
      await waitFor(() =>
        expect(
          screen.queryByRole('region', { name: 'Your booking' }),
        ).not.toBeInTheDocument(),
      )
      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
      expect(
        screen.getByRole('button', { name: 'Book this time' }),
      ).toBeInTheDocument()
    })
  })

  describe('R37: times in the browser zone', () => {
    it('R37: shows slot times in local time with a zone label', async () => {
      fakeSchedulingApi({ slots: [MON_9AM, TUE_12_9AM] })

      renderScheduler()

      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
      expect(await findSlot(TUE_12_9AM_TEXT)).toBeInTheDocument()
    })

    it('R37: a UTC instant past midnight shows on the local date', async () => {
      fakeSchedulingApi({ slots: [WED_930PM] })

      renderScheduler()

      expect(await findSlot(WED_930PM_TEXT)).toBeInTheDocument()
      expect(slotPicker()).not.toHaveTextContent(/Mar 7/)
      expect(slotPicker()).not.toHaveTextContent(/02:30|2:30/)
    })

    it('R37: the confirmation shows the local date, time and zone', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [WED_930PM] })
      renderScheduler()

      await book(user, WED_930PM_TEXT)

      const region = await findBookingRegion()
      expect(region).toHaveTextContent(WED_930PM_TEXT)
      expect(region).not.toHaveTextContent(/Mar 7/)
    })
  })

  describe('R34: keyboard and text states', () => {
    it('R34: books, reschedules and cancels with the keyboard alone', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM, WED_930PM] })
      renderScheduler()
      await findSlot(MON_9AM_TEXT)

      await tabTo(user, () => screen.getByRole('radio', { name: MON_9AM_TEXT }))
      await user.keyboard('{ArrowDown}')
      expect(screen.getByRole('radio', { name: TUE_1030AM_TEXT })).toBeChecked()
      await tabTo(user, () =>
        screen.getByRole('button', { name: 'Book this time' }),
      )
      await user.keyboard('{Enter}')
      expect(await findBookingRegion()).toHaveTextContent(TUE_1030AM_TEXT)

      await tabTo(user, () =>
        screen.getByRole('button', { name: 'Reschedule' }),
      )
      await user.keyboard('{Enter}')
      await findSlot(MON_9AM_TEXT)
      await tabTo(user, () => screen.getByRole('radio', { name: MON_9AM_TEXT }))
      await user.keyboard('{ArrowDown}')
      expect(screen.getByRole('radio', { name: WED_930PM_TEXT })).toBeChecked()
      await tabTo(user, () =>
        screen.getByRole('button', { name: 'Move to this time' }),
      )
      await user.keyboard('{Enter}')
      await waitFor(() =>
        expect(bookingRegion()).toHaveTextContent(WED_930PM_TEXT),
      )

      await tabTo(user, () =>
        screen.getByRole('button', { name: 'Cancel booking' }),
      )
      await user.keyboard('{Enter}')
      await tabTo(user, () =>
        screen.getByRole('button', { name: 'Yes, cancel it' }),
      )
      await user.keyboard('{Enter}')
      expect(await screen.findByRole('status')).toHaveTextContent(/cancelled/i)
    })

    it('R34: the selected slot is named in text, not shown by color alone', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()

      await user.click(await findSlot(TUE_1030AM_TEXT))

      expect(screen.getByRole('radio', { name: TUE_1030AM_TEXT })).toBeChecked()
      expect(screen.getByText(/^Selected:/)).toHaveTextContent(TUE_1030AM_TEXT)
    })

    it('R34: the booked state is shown in text', async () => {
      fakeSchedulingApi({
        slots: [MON_9AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })

      renderScheduler()

      const region = await findBookingRegion()
      expect(within(region).getAllByText(/booked/i)[0]).toBeVisible()
    })

    it('R34: the picker has no accessibility violations', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      const { container } = renderScheduler()
      await user.click(await findSlot(MON_9AM_TEXT))

      expect(await axe(container)).toHaveNoViolations()
    })

    it('R34: the booking, reschedule and cancel views have no accessibility violations', async () => {
      const user = userEvent.setup()
      fakeSchedulingApi({
        slots: [MON_9AM, TUE_1030AM],
        booking: { id: 'booking-1', slotId: MON_9AM.id },
      })
      const { container } = renderScheduler()
      await findBookingRegion()
      expect(await axe(container)).toHaveNoViolations()

      await user.click(screen.getByRole('button', { name: 'Reschedule' }))
      await findSlot(TUE_1030AM_TEXT)
      expect(await axe(container)).toHaveNoViolations()

      await user.click(screen.getByRole('button', { name: 'Cancel booking' }))
      await screen.findByRole('button', { name: 'Yes, cancel it' })
      expect(await axe(container)).toHaveNoViolations()
    })

    it('R34: the slot-taken error view has no accessibility violations', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      const { container } = renderScheduler()
      await findSlot(MON_9AM_TEXT)
      api.takeSlot(MON_9AM.id)
      await book(user, MON_9AM_TEXT)
      await screen.findByRole('alert')

      expect(await axe(container)).toHaveNoViolations()
    })
  })

  describe('R30: failures', () => {
    it('shows a retryable error when slots fail to load, and retrying loads them', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM] })
      api.failNext('GET', /^\/slots$/, () =>
        errorEnvelope(503, 'unavailable', 'Scheduling is unavailable.', [
          'retry',
        ]),
      )

      renderScheduler()

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'Scheduling is unavailable.',
      )
      await user.click(screen.getByRole('button', { name: 'Try again' }))
      expect(await findSlot(MON_9AM_TEXT)).toBeInTheDocument()
      expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    })

    it('keeps the user on the picker when booking fails on the network', async () => {
      const user = userEvent.setup()
      const api = fakeSchedulingApi({ slots: [MON_9AM, TUE_1030AM] })
      renderScheduler()
      await findSlot(MON_9AM_TEXT)
      api.failNext('POST', /^\/bookings$/, () =>
        Promise.reject(new TypeError('Failed to fetch')),
      )

      await book(user, MON_9AM_TEXT)

      expect(await screen.findByRole('alert')).toHaveTextContent(
        /could not reach the server/i,
      )
      expect(
        screen.queryByRole('region', { name: 'Your booking' }),
      ).not.toBeInTheDocument()
      expect(screen.getByRole('radio', { name: MON_9AM_TEXT })).toBeVisible()
    })

    it('asks a signed-out user to sign in instead of offering a retry', async () => {
      fakeSchedulingApi({ slots: [MON_9AM] })

      render(
        <Scheduler
          api={createApiClient({
            baseUrl: API_URL,
            getAccessToken: async () => null,
          })}
        />,
      )

      expect(await screen.findByRole('alert')).toHaveTextContent(/sign in/i)
      expect(
        screen.queryByRole('button', { name: 'Try again' }),
      ).not.toBeInTheDocument()
    })
  })
})
