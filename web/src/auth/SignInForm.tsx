'use client'

import { useId, useState, type FormEvent } from 'react'
import { getSupabaseClient } from './supabase'

interface SignInFormProps {
  onSignedIn: () => void
}

const WRONG_CREDENTIALS = 'That email and password do not match. Try again.'
const UNREACHABLE =
  'We could not reach the sign-in service. Check your connection and try again.'

export function SignInForm({ onSignedIn }: SignInFormProps) {
  const id = useId()
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    setSubmitting(true)
    setError(null)
    try {
      const { error: authError } =
        await getSupabaseClient().auth.signInWithPassword({
          email: String(form.get('email') ?? ''),
          password: String(form.get('password') ?? ''),
        })
      if (authError) {
        setError(WRONG_CREDENTIALS)
        return
      }
      onSignedIn()
    } catch {
      setError(UNREACHABLE)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <label htmlFor={`${id}-email`}>Email</label>
        <input
          id={`${id}-email`}
          name="email"
          type="email"
          autoComplete="email"
          required
        />
      </div>
      <div>
        <label htmlFor={`${id}-password`}>Password</label>
        <input
          id={`${id}-password`}
          name="password"
          type="password"
          autoComplete="current-password"
          required
        />
      </div>
      {error && <p role="alert">{error}</p>}
      <button type="submit" disabled={submitting}>
        Sign in
      </button>
    </form>
  )
}
