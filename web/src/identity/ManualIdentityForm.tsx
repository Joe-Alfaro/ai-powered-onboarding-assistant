'use client'

import { useState, type FormEvent } from 'react'
import type { ApiClient, ApiError } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'
import { identityValuesOf } from './documents'
import { IdentityFields } from './IdentityFields'

interface ManualIdentityFormProps {
  api: ApiClient
  onSaved: () => void
}

// Entering every field by hand, with no upload at all (R10).
export function ManualIdentityForm({ api, onSaved }: ManualIdentityFormProps) {
  const [error, setError] = useState<ApiError | null>(null)
  const [saving, setSaving] = useState(false)

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const values = identityValuesOf(event.currentTarget)
    setSaving(true)
    setError(null)
    try {
      await api.request('/onboarding/identity', {
        method: 'POST',
        body: values,
      })
      onSaved()
    } catch (caught) {
      setError(toApiError(caught))
    } finally {
      setSaving(false)
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      <h2>Enter your details</h2>
      <IdentityFields />
      {error && <ErrorNotice error={error} />}
      <button type="submit" disabled={saving}>
        Save and continue
      </button>
    </form>
  )
}
