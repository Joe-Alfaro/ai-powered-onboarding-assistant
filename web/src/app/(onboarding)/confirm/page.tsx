'use client'

import { useRouter, useSearchParams } from 'next/navigation'
import { Suspense } from 'react'
import { useApiClient } from '@/api/useApiClient'
import { ConfirmIdentityForm } from '@/identity/ConfirmIdentityForm'

function ConfirmStep() {
  const router = useRouter()
  const api = useApiClient()
  const documentId = useSearchParams().get('document')

  function enterManually() {
    router.push('/identity/manual')
  }

  if (!documentId) {
    return (
      <>
        <p>There is no uploaded ID to check.</p>
        <button type="button" onClick={enterManually}>
          Skip and enter details manually
        </button>
      </>
    )
  }

  return (
    <ConfirmIdentityForm
      api={api}
      documentId={documentId}
      onConfirmed={() => router.push('/schedule')}
      onManualEntry={enterManually}
    />
  )
}

// useSearchParams needs a Suspense boundary for the static build.
export default function ConfirmPage() {
  return (
    <>
      <h1>Confirm your details</h1>
      <Suspense>
        <ConfirmStep />
      </Suspense>
    </>
  )
}
