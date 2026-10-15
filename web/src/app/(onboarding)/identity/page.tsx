'use client'

import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { useApiClient } from '@/api/useApiClient'
import { IdentityStep } from '@/identity/IdentityStep'
import { SupportiveContent } from '@/support/SupportiveContent'
import { createTriggerEngine } from '@/support/triggerEngine'

export default function IdentityPage() {
  const router = useRouter()
  const api = useApiClient()
  const [engine] = useState(() => createTriggerEngine())

  useEffect(() => {
    engine.start()
    return () => engine.stop()
  }, [engine])

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
      <SupportiveContent engine={engine} />
    </>
  )
}
