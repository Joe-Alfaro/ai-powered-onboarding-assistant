'use client'

import { useRouter } from 'next/navigation'
import { useEffect } from 'react'
import { ErrorNotice } from '@/api/ErrorNotice'
import { getAccessToken } from '@/auth/supabase'
import { useGoToCurrentStep } from '@/onboarding/useGoToCurrentStep'

// Sends a signed-out visitor to sign in and a signed-in user to their current
// step.
export default function Home() {
  const router = useRouter()
  const { goToCurrentStep, error } = useGoToCurrentStep()

  useEffect(() => {
    let current = true
    void getAccessToken().then((token) => {
      if (!current) return
      if (token) void goToCurrentStep()
      else router.replace('/sign-in')
    })
    return () => {
      current = false
    }
  }, [goToCurrentStep, router])

  return (
    <main>
      <h1>Onboarding assistant</h1>
      {error && (
        <ErrorNotice error={error} onRetry={() => void goToCurrentStep()} />
      )}
    </main>
  )
}
