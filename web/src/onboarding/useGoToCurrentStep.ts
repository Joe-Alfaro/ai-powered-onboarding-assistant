'use client'

import { useRouter } from 'next/navigation'
import { useCallback, useState } from 'react'
import type { ApiError } from '@/api/client'
import { toApiError } from '@/api/toApiError'
import { useApiClient } from '@/api/useApiClient'
import { currentStepPath } from './onboardingApi'

const SIGN_IN_PATH = '/sign-in'

// Asks the API where the user is in the flow and replaces to that step, so
// Back doesn't return to the page they left (R8). A 401 goes to sign in; any
// other failure is returned for the page to show with a retry (R30).
export function useGoToCurrentStep() {
  const router = useRouter()
  const api = useApiClient()
  const [error, setError] = useState<ApiError | null>(null)

  const goToCurrentStep = useCallback(async () => {
    setError(null)
    try {
      router.replace(await currentStepPath(api))
    } catch (caught) {
      const apiError = toApiError(caught)
      if (apiError.status === 401) router.replace(SIGN_IN_PATH)
      else setError(apiError)
    }
  }, [api, router])

  return { goToCurrentStep, error }
}
