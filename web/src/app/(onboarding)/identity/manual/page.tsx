'use client'

import { useRouter } from 'next/navigation'
import { useApiClient } from '@/api/useApiClient'
import { ManualIdentityForm } from '@/identity/ManualIdentityForm'

export default function ManualIdentityPage() {
  const router = useRouter()
  const api = useApiClient()

  return (
    <>
      <h1>Your details</h1>
      <ManualIdentityForm api={api} onSaved={() => router.push('/schedule')} />
    </>
  )
}
