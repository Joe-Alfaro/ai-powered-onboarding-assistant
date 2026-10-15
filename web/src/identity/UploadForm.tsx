'use client'

import { useId, useState, type FormEvent } from 'react'
import { ApiError, type ApiClient } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'
import type { TriggerEngine } from '@/support/triggerEngine'
import type { DocumentEnvelope, IdentityDocument } from './documents'

export const DEFAULT_MAX_UPLOAD_MB = 10
const BYTES_PER_MB = 1024 * 1024

// Read at render time so tests and deployments can set it. It matches the
// API's MAX_UPLOAD_MB; the server stays the authority (R14).
export function maxUploadMb() {
  const mb = Number(process.env.NEXT_PUBLIC_MAX_UPLOAD_MB)
  if (!Number.isFinite(mb) || mb <= 0) return DEFAULT_MAX_UPLOAD_MB
  return mb
}

function clientRefusal(code: string, message: string) {
  return new ApiError({ status: null, code, message, actions: [] })
}

const UNREADABLE = clientRefusal(
  'manual_entry',
  'We could not read your ID clearly enough. Please try another photo, or enter your details manually.',
)

interface UploadFormProps {
  api: ApiClient
  engine: TriggerEngine
  onUploaded: (document: IdentityDocument) => void
  onConsentRequired: (message: string) => void
}

export function UploadForm({
  api,
  engine,
  onUploaded,
  onConsentRequired,
}: UploadFormProps) {
  const id = useId()
  const [file, setFile] = useState<File | null>(null)
  const [error, setError] = useState<ApiError | null>(null)
  const [uploading, setUploading] = useState(false)
  const limitMb = maxUploadMb()

  // Every failed or unreadable upload fires the upload-failure content (R9).
  function fail(failure: ApiError) {
    setError(failure)
    engine.reportUpload({ ok: false, status: failure.status ?? undefined })
  }

  async function upload(chosen: File) {
    if (chosen.size > limitMb * BYTES_PER_MB) {
      fail(
        clientRefusal(
          'file_too_large',
          `That file is over the ${limitMb} MB limit. Please choose a smaller photo.`,
        ),
      )
      return
    }
    const body = new FormData()
    body.append('file', chosen)
    setUploading(true)
    setError(null)
    try {
      const { document } = await api.request<DocumentEnvelope>('/documents', {
        method: 'POST',
        body,
      })
      if (document.manual_entry) {
        fail(UNREADABLE)
        return
      }
      onUploaded(document)
    } catch (caught) {
      const failure = toApiError(caught)
      engine.reportUpload({ ok: false, status: failure.status ?? undefined })
      if (failure.code === 'consent_required') {
        onConsentRequired(failure.message)
        return
      }
      setError(failure)
    } finally {
      setUploading(false)
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!file) {
      setError(clientRefusal('no_file', 'Please choose a photo of your ID.'))
      return
    }
    void upload(file)
  }

  return (
    <form onSubmit={handleSubmit}>
      <h2>Upload your ID</h2>
      <div>
        <label htmlFor={`${id}-file`}>Photo of your ID</label>
        <p id={`${id}-hint`}>A JPEG, PNG or HEIC photo, up to {limitMb} MB.</p>
        <input
          id={`${id}-file`}
          type="file"
          accept="image/jpeg,image/png,image/heic,image/heif"
          aria-describedby={`${id}-hint`}
          onChange={(event) => setFile(event.target.files?.[0] ?? null)}
        />
      </div>
      {error && (
        <ErrorNotice error={error} onRetry={() => file && upload(file)} />
      )}
      <button type="submit" disabled={uploading}>
        Upload photo
      </button>
    </form>
  )
}
