'use client'

import {
  useCallback,
  useEffect,
  useId,
  useState,
  type FormEvent,
  type ReactNode,
} from 'react'
import { ApiError, type ApiClient } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { formatLocalDateTime } from '@/time/formatLocalDateTime'

// Books, moves and cancels the user's call. The booking is read from the API
// on every load and never kept in browser storage, so any session sees it
// (R8).

interface Slot {
  id: string
  starts_at: string
  ends_at: string
}

interface Booking {
  id: string
  status: 'active' | 'cancelled'
  slot: Slot
}

interface SchedulerProps {
  api: ApiClient
  // Shown once a call is booked, such as a link on to the next step.
  next?: ReactNode
}

type Mode = 'viewing' | 'rescheduling' | 'confirming-cancel'

const SLOT_TAKEN_MESSAGE =
  'That time was just taken by someone else. Please pick another time.'

function toApiError(error: unknown) {
  if (error instanceof ApiError) return error
  return new ApiError({
    status: null,
    code: 'unexpected',
    message: 'Something went wrong. Please try again.',
    actions: ['retry'],
  })
}

function messageFor(error: ApiError) {
  return error.code === 'slot_taken' ? SLOT_TAKEN_MESSAGE : error.message
}

export function Scheduler({ api, next }: SchedulerProps) {
  const id = useId()
  const [slots, setSlots] = useState<Slot[] | null>(null)
  const [booking, setBooking] = useState<Booking | null>(null)
  const [loadError, setLoadError] = useState<ApiError | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)
  const [status, setStatus] = useState<string | null>(null)
  const [mode, setMode] = useState<Mode>('viewing')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const fetchSlots = useCallback(
    async () => (await api.request<{ slots: Slot[] }>('/slots')).slots,
    [api],
  )

  // Bumped by "Try again" to run the load again.
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let current = true
    Promise.all([
      fetchSlots(),
      api.request<{ bookings: Booking[] }>('/bookings'),
    ]).then(
      ([openSlots, { bookings }]) => {
        if (!current) return
        setSlots(openSlots)
        setBooking(bookings[0] ?? null)
      },
      (error: unknown) => {
        if (current) setLoadError(toApiError(error))
      },
    )
    return () => {
      current = false
    }
  }, [api, fetchSlots, attempt])

  function retryLoad() {
    setLoadError(null)
    setSlots(null)
    setAttempt((count) => count + 1)
  }

  // The open slots change with every booking, so they are read again after
  // each change. If that read fails, the booked slot is at least left out.
  async function freshSlots(without?: string) {
    try {
      return await fetchSlots()
    } catch {
      return (slots ?? []).filter((slot) => slot.id !== without)
    }
  }

  function startAction() {
    setBusy(true)
    setActionError(null)
    setStatus(null)
  }

  async function submitSlot(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedId || busy) return
    const moving = booking !== null
    startAction()
    try {
      const { booking: saved } = await api.request<{ booking: Booking }>(
        moving ? `/bookings/${booking.id}` : '/bookings',
        { method: moving ? 'PATCH' : 'POST', body: { slot_id: selectedId } },
      )
      setSlots(await freshSlots(saved.slot.id))
      setBooking(saved)
      setMode('viewing')
      setSelectedId(null)
      setStatus(moving ? 'Your call is rescheduled.' : 'Your call is booked.')
    } catch (error) {
      const apiError = toApiError(error)
      if (apiError.code === 'slot_taken') {
        // Someone else got there first: show what is still open (R7).
        setSlots(await freshSlots(selectedId))
        setSelectedId(null)
      }
      setActionError(messageFor(apiError))
    } finally {
      setBusy(false)
    }
  }

  async function cancelBooking() {
    if (!booking || busy) return
    startAction()
    try {
      await api.request(`/bookings/${booking.id}`, { method: 'DELETE' })
      setSlots(await freshSlots())
      setBooking(null)
      setMode('viewing')
      setStatus('Your call is cancelled.')
    } catch (error) {
      setActionError(messageFor(toApiError(error)))
    } finally {
      setBusy(false)
    }
  }

  function changeMode(next: Mode) {
    setMode(next)
    setActionError(null)
    setStatus(null)
    setSelectedId(null)
  }

  if (loadError) return <ErrorNotice error={loadError} onRetry={retryLoad} />
  if (!slots) return <p>Loading open times…</p>

  const selected = slots.find((slot) => slot.id === selectedId)
  const showPicker = !booking || mode === 'rescheduling'
  const bookedTime = booking && formatLocalDateTime(booking.slot.starts_at)

  return (
    <div>
      {status && <p role="status">{status}</p>}
      {actionError && <p role="alert">{actionError}</p>}

      {booking && (
        <section aria-labelledby={`${id}-booking`}>
          <h2 id={`${id}-booking`}>Your booking</h2>
          <p>
            Booked: <strong>{bookedTime}</strong>
          </p>
          {mode === 'confirming-cancel' ? (
            <div>
              <p>Cancel your call on {bookedTime}?</p>
              <button type="button" onClick={cancelBooking} disabled={busy}>
                Yes, cancel it
              </button>
              <button type="button" onClick={() => changeMode('viewing')}>
                Keep my booking
              </button>
            </div>
          ) : (
            <div>
              <button type="button" onClick={() => changeMode('rescheduling')}>
                Reschedule
              </button>
              <button
                type="button"
                onClick={() => changeMode('confirming-cancel')}
              >
                Cancel booking
              </button>
            </div>
          )}
        </section>
      )}

      {booking && mode === 'viewing' && next}

      {showPicker &&
        (slots.length === 0 ? (
          <p>No open times right now. Please check back later.</p>
        ) : (
          <form onSubmit={submitSlot}>
            <fieldset>
              <legend>Available times</legend>
              {slots.map((slot) => (
                <div key={slot.id}>
                  <input
                    type="radio"
                    id={`${id}-${slot.id}`}
                    name={`${id}-slot`}
                    value={slot.id}
                    checked={slot.id === selectedId}
                    onChange={() => setSelectedId(slot.id)}
                  />
                  <label htmlFor={`${id}-${slot.id}`}>
                    {formatLocalDateTime(slot.starts_at)}
                  </label>
                </div>
              ))}
            </fieldset>
            {selected && (
              <p>Selected: {formatLocalDateTime(selected.starts_at)}</p>
            )}
            <button type="submit" disabled={!selected || busy}>
              {booking ? 'Move to this time' : 'Book this time'}
            </button>
          </form>
        ))}
    </div>
  )
}
