'use client'

import type { ApiError } from './client'

interface ErrorNoticeProps {
  error: ApiError
  onRetry?: () => void
  onManualEntry?: () => void
}

// Shows an API error with the choices its envelope offers (R16, R30).
export function ErrorNotice({
  error,
  onRetry,
  onManualEntry,
}: ErrorNoticeProps) {
  const canRetry = error.actions.includes('retry') && onRetry
  const canEnterManually =
    error.actions.includes('manual_entry') && onManualEntry

  return (
    <div role="alert">
      <p>{error.message}</p>
      {canRetry && (
        <button type="button" onClick={onRetry}>
          Try again
        </button>
      )}
      {canEnterManually && (
        <button type="button" onClick={onManualEntry}>
          Enter details manually
        </button>
      )}
    </div>
  )
}
