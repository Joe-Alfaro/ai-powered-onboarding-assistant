'use client'

import { useEffect, useState, type FormEvent } from 'react'
import type { ApiClient, ApiError } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'
import {
  identityValuesOf,
  type DocumentEnvelope,
  type DraftFields,
} from './documents'
import { IdentityFields } from './IdentityFields'

interface ConfirmIdentityFormProps {
  api: ApiClient
  documentId: string
  onConfirmed: () => void
  onManualEntry: () => void
}

type Draft =
  | { state: 'loading' }
  | { state: 'failed'; error: ApiError }
  | { state: 'loaded'; fields: DraftFields }

// Shows the OCR draft for review. Nothing is saved until the user confirms,
// and then the form's values are sent exactly as they stand (R5).
export function ConfirmIdentityForm({
  api,
  documentId,
  onConfirmed,
  onManualEntry,
}: ConfirmIdentityFormProps) {
  const [draft, setDraft] = useState<Draft>({ state: 'loading' })
  const [attempt, setAttempt] = useState(0)
  const [saveError, setSaveError] = useState<ApiError | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let current = true
    api
      .request<DocumentEnvelope>(`/documents/${encodeURIComponent(documentId)}`)
      .then(({ document }) => {
        if (current) setDraft({ state: 'loaded', fields: document.fields })
      })
      .catch((caught: unknown) => {
        if (current) setDraft({ state: 'failed', error: toApiError(caught) })
      })
    return () => {
      current = false
    }
  }, [api, documentId, attempt])

  function reload() {
    setDraft({ state: 'loading' })
    setAttempt((count) => count + 1)
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const values = identityValuesOf(event.currentTarget)
    setSaving(true)
    setSaveError(null)
    try {
      await api.request(
        `/documents/${encodeURIComponent(documentId)}/confirm`,
        { method: 'POST', body: values },
      )
      onConfirmed()
    } catch (caught) {
      setSaveError(toApiError(caught))
    } finally {
      setSaving(false)
    }
  }

  const skipButton = (
    <button type="button" onClick={onManualEntry}>
      Skip and enter details manually
    </button>
  )

  if (draft.state !== 'loaded') {
    return (
      <>
        {draft.state === 'loading' ? (
          <p>Loading the details read from your ID…</p>
        ) : (
          <ErrorNotice error={draft.error} onRetry={reload} />
        )}
        {skipButton}
      </>
    )
  }

  return (
    <>
      <form onSubmit={handleSubmit}>
        <h2>Check the details read from your ID</h2>
        <p>
          Check each field and correct anything that is wrong. Nothing is saved
          until you confirm.
        </p>
        <IdentityFields draft={draft.fields} />
        {saveError && <ErrorNotice error={saveError} />}
        <button type="submit" disabled={saving}>
          Confirm details
        </button>
      </form>
      {skipButton}
    </>
  )
}
