'use client'

import { ErrorNotice } from '@/api/ErrorNotice'
import { SignInForm } from '@/auth/SignInForm'
import { useGoToCurrentStep } from '@/onboarding/useGoToCurrentStep'

export default function SignInPage() {
  const { goToCurrentStep, error } = useGoToCurrentStep()

  return (
    <main>
      <h1>Sign in</h1>
      <SignInForm onSignedIn={() => void goToCurrentStep()} />
      {error && (
        <ErrorNotice error={error} onRetry={() => void goToCurrentStep()} />
      )}
    </main>
  )
}
