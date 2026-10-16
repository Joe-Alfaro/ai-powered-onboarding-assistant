'use client'

import { useId, useState, type FormEvent } from 'react'
import type { ApiClient, ApiError } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'

// The web app owns the consent text, so its version lives beside it. Change
// the version whenever the text below changes (R12).
export const CONSENT_TEXT_VERSION = '2026-10-15'

interface ConsentFormProps {
  api: ApiClient
  onConsented: () => void
  // Shown when the server sent the user back here, such as a 403 on upload.
  notice?: string | null
}

const NOT_TICKED = 'Please tick the box to give your consent before continuing.'

export function ConsentForm({ api, onConsented, notice }: ConsentFormProps) {
  const id = useId()
  const [agreed, setAgreed] = useState(false)
  const [message, setMessage] = useState(notice ?? null)
  const [error, setError] = useState<ApiError | null>(null)
  const [submitting, setSubmitting] = useState(false)

  async function sendConsent() {
    setSubmitting(true)
    setMessage(null)
    setError(null)
    try {
      await api.request('/consents', {
        method: 'POST',
        body: { text_version: CONSENT_TEXT_VERSION },
      })
      onConsented()
    } catch (caught) {
      setError(toApiError(caught))
    } finally {
      setSubmitting(false)
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!agreed) {
      setError(null)
      setMessage(NOT_TICKED)
      return
    }
    void sendConsent()
  }

  return (
    <section aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`}>Your consent</h2>
      <h3>What we collect</h3>
      <ul>
        <li>Your full name, date of birth and address</li>
        <li>A photo of your ID, which we read to fill in those details</li>
      </ul>
      <h3>Why we need it</h3>
      <p>
        We use these details to verify who you are and set up your account. The
        photo is read on our own servers and is never sent to an AI service.
      </p>
      <h3>How long we keep it</h3>
      <p>
        We delete the photo as soon as you confirm your details, or after one
        hour if you don&apos;t. You can withdraw consent or ask us to delete
        your data at any time from the privacy page.
      </p>
      <p>Consent text version: {CONSENT_TEXT_VERSION}</p>
      <form onSubmit={handleSubmit}>
        <div>
          <input
            id={`${id}-agree`}
            type="checkbox"
            checked={agreed}
            onChange={(event) => setAgreed(event.target.checked)}
          />
          <label htmlFor={`${id}-agree`}>
            I agree to the collection and use of my details as described above.
          </label>
        </div>
        {message && <p role="alert">{message}</p>}
        {error && <ErrorNotice error={error} onRetry={sendConsent} />}
        <button type="submit" disabled={submitting}>
          Continue
        </button>
      </form>
    </section>
  )
}
