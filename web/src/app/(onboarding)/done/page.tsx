'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import type { ApiError } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'
import { useApiClient } from '@/api/useApiClient'
import { AssessmentSummary } from '@/chat/AssessmentSummary'
import {
  fetchOnboarding,
  type OnboardingStatus,
} from '@/onboarding/onboardingApi'
import { formatLocalDateTime } from '@/time/formatLocalDateTime'

// What the user has finished, read from the API on every visit so any
// session shows the same summary (R8). Identity is shown as a status only.

interface Booking {
  id: string
  status: 'active' | 'cancelled'
  slot: { id: string; starts_at: string; ends_at: string }
}

interface Summary {
  onboarding: OnboardingStatus
  booking: Booking | null
}

function IdentityStatus({
  identity,
}: {
  identity: OnboardingStatus['identity']
}) {
  if (!identity.confirmed) {
    return (
      <p>
        Your details are not confirmed yet.{' '}
        <Link href="/identity">Confirm your details</Link>
      </p>
    )
  }
  return (
    <p>
      {identity.source === 'manual'
        ? 'Confirmed from the details you entered.'
        : 'Confirmed from your ID photo.'}
    </p>
  )
}

function BookingStatus({ booking }: { booking: Booking | null }) {
  if (!booking) {
    return (
      <p>
        No call booked. <Link href="/schedule">Schedule a call</Link>
      </p>
    )
  }
  return <p>Your call is on {formatLocalDateTime(booking.slot.starts_at)}.</p>
}

export default function DonePage() {
  const api = useApiClient()
  const [summary, setSummary] = useState<Summary | null>(null)
  const [loadError, setLoadError] = useState<ApiError | null>(null)
  // Bumped by "Try again" to run the load again.
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let current = true
    Promise.all([
      fetchOnboarding(api),
      api.request<{ bookings: Booking[] }>('/bookings'),
    ]).then(
      ([onboarding, { bookings }]) => {
        if (!current) return
        setSummary({
          onboarding,
          booking: bookings.find(({ status }) => status === 'active') ?? null,
        })
      },
      (error: unknown) => {
        if (current) setLoadError(toApiError(error))
      },
    )
    return () => {
      current = false
    }
  }, [api, attempt])

  function retryLoad() {
    setLoadError(null)
    setAttempt((count) => count + 1)
  }

  return (
    <>
      <h1>You&apos;re all set</h1>
      {loadError && <ErrorNotice error={loadError} onRetry={retryLoad} />}
      {summary && (
        <>
          {summary.onboarding.assessment ? (
            <AssessmentSummary assessment={summary.onboarding.assessment} />
          ) : (
            <p>
              Your assessment is not saved yet.{' '}
              <Link href="/chat">Go back to the chat</Link>
            </p>
          )}
          <section aria-labelledby="done-identity-heading">
            <h2 id="done-identity-heading">Your details</h2>
            <IdentityStatus identity={summary.onboarding.identity} />
          </section>
          <section aria-labelledby="done-booking-heading">
            <h2 id="done-booking-heading">Your booking</h2>
            <BookingStatus booking={summary.booking} />
          </section>
        </>
      )}
    </>
  )
}
