import {
  errorEnvelope,
  headerOf,
  installFetch,
  jsonResponse,
  type FakeResponse,
} from './fetch'

// A stand-in for the Rails scheduling API at the fetch boundary. It answers
// the way api/spec/requests/{slots,bookings}_spec.rb say the real API does:
// GET /slots lists open slots, GET /bookings lists the caller's active
// bookings, POST /bookings books, PATCH /bookings/:id reschedules in place and
// DELETE /bookings/:id cancels. Times are ISO-8601 UTC with a Z suffix.

export interface FakeSlot {
  id: string
  starts_at: string
  ends_at: string
}

export interface FakeBooking {
  id: string
  status: 'active' | 'cancelled'
  slot: FakeSlot
}

export interface RecordedRequest {
  method: string
  path: string
  body: unknown
  authorization: string | null
}

// The real API's 409 message for a slot someone else holds.
export const SLOT_TAKEN_MESSAGE = 'That slot is already booked.'

export function slotAt(id: string, startsAt: string, minutes = 30): FakeSlot {
  const ends = new Date(new Date(startsAt).getTime() + minutes * 60_000)
  return {
    id,
    starts_at: startsAt,
    ends_at: ends.toISOString().replace('.000Z', 'Z'),
  }
}

interface FakeSchedulingApiOptions {
  slots: FakeSlot[]
  // The signed-in user's existing active booking, if any.
  booking?: { id: string; slotId: string }
}

export function fakeSchedulingApi({
  slots,
  booking,
}: FakeSchedulingApiOptions) {
  const fetchMock = installFetch()
  const requests: RecordedRequest[] = []
  const takenByOthers = new Set<string>()
  const overrides: Array<{
    method: string
    path: RegExp
    response: () => FakeResponse | Promise<FakeResponse>
  }> = []
  let active: FakeBooking | null = null
  let bookingCount = 0

  function slotById(id: string) {
    return slots.find((slot) => slot.id === id)
  }

  function isOpen(slot: FakeSlot) {
    return !takenByOthers.has(slot.id) && active?.slot.id !== slot.id
  }

  if (booking) {
    const slot = slotById(booking.slotId)
    if (!slot) throw new Error(`No slot ${booking.slotId} to book`)
    active = { id: booking.id, status: 'active', slot }
  }

  function notFound() {
    return errorEnvelope(404, 'not_found', 'Not found.', [])
  }

  function slotTaken() {
    return errorEnvelope(409, 'slot_taken', SLOT_TAKEN_MESSAGE, [])
  }

  function handle(method: string, path: string, body: unknown) {
    const slotId = (body as { slot_id?: string } | undefined)?.slot_id

    if (method === 'GET' && path === '/slots') {
      return jsonResponse(200, { slots: slots.filter(isOpen) })
    }
    if (method === 'GET' && path === '/bookings') {
      return jsonResponse(200, { bookings: active ? [active] : [] })
    }
    if (method === 'POST' && path === '/bookings') {
      const slot = slotId ? slotById(slotId) : undefined
      if (!slot) return notFound()
      if (active) {
        return errorEnvelope(
          409,
          'booking_exists',
          'You already have a booking.',
          [],
        )
      }
      if (takenByOthers.has(slot.id)) return slotTaken()
      bookingCount += 1
      active = { id: `booking-${bookingCount}`, status: 'active', slot }
      return jsonResponse(201, { booking: active })
    }

    const match = path.match(/^\/bookings\/([^/]+)$/)
    if (!match) return notFound()
    if (!active || active.id !== match[1]) return notFound()

    if (method === 'GET') return jsonResponse(200, { booking: active })
    if (method === 'PATCH') {
      const slot = slotId ? slotById(slotId) : undefined
      if (!slot) return notFound()
      if (!isOpen(slot)) return slotTaken()
      active = { ...active, slot }
      return jsonResponse(200, { booking: active })
    }
    if (method === 'DELETE') {
      const cancelled: FakeBooking = { ...active, status: 'cancelled' }
      active = null
      return jsonResponse(200, { booking: cancelled })
    }
    return notFound()
  }

  fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
    const { pathname } = new URL(url)
    const method = (init?.method ?? 'GET').toUpperCase()
    const body =
      typeof init?.body === 'string' ? JSON.parse(init.body) : undefined
    requests.push({
      method,
      path: pathname,
      body,
      authorization: headerOf(init, 'Authorization'),
    })

    const overrideIndex = overrides.findIndex(
      (override) => override.method === method && override.path.test(pathname),
    )
    if (overrideIndex >= 0) {
      const [override] = overrides.splice(overrideIndex, 1)
      return override.response()
    }
    return handle(method, pathname, body)
  })

  return {
    fetchMock,
    requests,
    // Another user books this slot. The page's list is now stale.
    takeSlot(id: string) {
      takenByOthers.add(id)
    },
    // Answers the next matching request with this response instead.
    failNext(
      method: string,
      path: RegExp,
      response: () => FakeResponse | Promise<FakeResponse>,
    ) {
      overrides.push({ method, path, response })
    },
    activeBooking() {
      return active
    },
    requestsTo(method: string, path: string | RegExp) {
      return requests.filter(
        (request) =>
          request.method === method &&
          (typeof path === 'string'
            ? request.path === path
            : path.test(request.path)),
      )
    },
  }
}
