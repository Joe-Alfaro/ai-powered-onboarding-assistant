'use client'

import { useState } from 'react'
import type { ApiClient } from '@/api/client'
import type { TriggerEngine } from '@/support/triggerEngine'
import { ConsentForm } from './ConsentForm'
import type { IdentityDocument } from './documents'
import { UploadForm } from './UploadForm'

interface IdentityStepProps {
  api: ApiClient
  engine: TriggerEngine
  onUploaded: (document: IdentityDocument) => void
  onManualEntry: () => void
}

// Consent first; the upload form exists only once POST /consents has
// succeeded (R12). There is no consent lookup, so every visit asks again.
export function IdentityStep({
  api,
  engine,
  onUploaded,
  onManualEntry,
}: IdentityStepProps) {
  const [consented, setConsented] = useState(false)
  const [consentNotice, setConsentNotice] = useState<string | null>(null)

  function returnToConsent(message: string) {
    setConsentNotice(message)
    setConsented(false)
  }

  return (
    <>
      {consented ? (
        <UploadForm
          api={api}
          engine={engine}
          onUploaded={onUploaded}
          onConsentRequired={returnToConsent}
        />
      ) : (
        <ConsentForm
          api={api}
          notice={consentNotice}
          onConsented={() => setConsented(true)}
        />
      )}
      <button type="button" onClick={onManualEntry}>
        Skip and enter details manually
      </button>
    </>
  )
}
