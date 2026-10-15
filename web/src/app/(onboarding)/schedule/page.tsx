'use client'

import { useMemo } from 'react'
import { createApiClient } from '@/api/client'
import { getAccessToken } from '@/auth/supabase'
import { Scheduler } from '@/schedule/Scheduler'

export default function SchedulePage() {
  // Built on render, not at import, so the public variable is read when the
  // app (or a test) has set it.
  const api = useMemo(
    () =>
      createApiClient({
        baseUrl: process.env.NEXT_PUBLIC_API_URL ?? '',
        getAccessToken,
      }),
    [],
  )

  return (
    <>
      <h1>Schedule a call</h1>
      <Scheduler api={api} />
    </>
  )
}
