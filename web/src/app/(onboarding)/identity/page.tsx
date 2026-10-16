'use client'

import { useRouter } from 'next/navigation'
import { useApiClient } from '@/api/useApiClient'
import { IdentityStep } from '@/identity/IdentityStep'
import { SupportiveContent } from '@/support/SupportiveContent'
import { useStepTriggerEngine } from '@/support/TriggerEngineContext'

export default function IdentityPage() {
  const router = useRouter()
  const api = useApiClient()
  const { engine, ownsEngine } = useStepTriggerEngine()

  return (
    <>
      <h1>Your ID</h1>
      <IdentityStep
        api={api}
        engine={engine}
        onUploaded={({ id }) =>
          router.push(`/confirm?document=${encodeURIComponent(id)}`)
        }
        onManualEntry={() => router.push('/identity/manual')}
      />
      {ownsEngine && <SupportiveContent engine={engine} />}
    </>
  )
}
