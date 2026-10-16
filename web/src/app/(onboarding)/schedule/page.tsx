'use client'

import { useApiClient } from '@/api/useApiClient'
import { Scheduler } from '@/schedule/Scheduler'

export default function SchedulePage() {
  const api = useApiClient()

  return (
    <>
      <h1>Schedule a call</h1>
      <Scheduler api={api} />
    </>
  )
}
