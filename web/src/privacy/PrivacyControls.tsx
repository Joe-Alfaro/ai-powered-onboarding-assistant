'use client'

import { useEffect, useId, useRef, useState, type KeyboardEvent } from 'react'
import type { ApiClient, ApiError } from '@/api/client'
import { ErrorNotice } from '@/api/ErrorNotice'
import { toApiError } from '@/api/toApiError'

type ActionId = 'withdraw' | 'delete'

interface PrivacyAction {
  label: string
  title: string
  explanation: string
  confirmLabel: string
  path: string
  result: string
}

// R13. The endpoints are the seam set by the tests: each answers 204.
const ACTIONS: Record<ActionId, PrivacyAction> = {
  withdraw: {
    label: 'Withdraw consent',
    title: 'Withdraw your consent?',
    explanation:
      'We will stop using your details, and permanently remove your ID photo and the details read from it. This cannot be undone. You can give consent again later.',
    confirmLabel: 'Yes, withdraw consent',
    path: '/consents',
    result: 'Your consent has been withdrawn.',
  },
  delete: {
    label: 'Delete my data',
    title: 'Delete all of your data?',
    explanation:
      'We will permanently remove your account, your ID photo, the details read from it and your chat messages. This cannot be undone.',
    confirmLabel: 'Yes, delete my data',
    path: '/account',
    result: 'Your data has been deleted.',
  },
}

interface PrivacyControlsProps {
  api: ApiClient
  onDeleted?: () => void
}

export function PrivacyControls({ api, onDeleted }: PrivacyControlsProps) {
  const id = useId()
  const [open, setOpen] = useState<ActionId | null>(null)
  const [error, setError] = useState<{
    action: ActionId
    error: ApiError
  } | null>(null)
  const [result, setResult] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const openers = useRef<Partial<Record<ActionId, HTMLButtonElement | null>>>(
    {},
  )
  const cancelRef = useRef<HTMLButtonElement>(null)

  // Focus moves into the confirmation when it opens (R34).
  useEffect(() => {
    if (open) cancelRef.current?.focus()
  }, [open])

  function close() {
    const opener = open && openers.current[open]
    setOpen(null)
    opener?.focus()
  }

  async function run(action: ActionId) {
    setOpen(null)
    setBusy(true)
    setError(null)
    setResult(null)
    try {
      await api.request(ACTIONS[action].path, { method: 'DELETE' })
      setResult(ACTIONS[action].result)
      if (action === 'delete') onDeleted?.()
    } catch (caught) {
      setError({ action, error: toApiError(caught) })
    } finally {
      setBusy(false)
    }
  }

  function handleKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === 'Escape') {
      event.preventDefault()
      close()
    }
  }

  const dialog = open && ACTIONS[open]

  return (
    <>
      <div>
        {(Object.keys(ACTIONS) as ActionId[]).map((action) => (
          <button
            key={action}
            type="button"
            ref={(button) => {
              openers.current[action] = button
            }}
            disabled={busy}
            onClick={() => setOpen(action)}
          >
            {ACTIONS[action].label}
          </button>
        ))}
      </div>
      {dialog && open && (
        <div
          role="alertdialog"
          aria-labelledby={`${id}-title`}
          aria-describedby={`${id}-explanation`}
          onKeyDown={handleKeyDown}
        >
          <h2 id={`${id}-title`}>{dialog.title}</h2>
          <p id={`${id}-explanation`}>{dialog.explanation}</p>
          <button type="button" ref={cancelRef} onClick={close}>
            Cancel
          </button>
          <button type="button" onClick={() => run(open)}>
            {dialog.confirmLabel}
          </button>
        </div>
      )}
      {error && (
        <ErrorNotice error={error.error} onRetry={() => run(error.action)} />
      )}
      <div role="status">{result && <p>{result}</p>}</div>
    </>
  )
}
