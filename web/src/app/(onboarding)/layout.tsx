'use client'

import { usePathname, useRouter } from 'next/navigation'
import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { UnauthorizedContext } from '@/api/UnauthorizedContext'
import { getAccessToken, getSupabaseClient } from '@/auth/supabase'
import { AppShell } from '@/shell/AppShell'
import { stepFromPath } from '@/shell/steps'
import { SupportiveContent } from '@/support/SupportiveContent'
import { TriggerEngineContext } from '@/support/TriggerEngineContext'
import { createTriggerEngine } from '@/support/triggerEngine'

const SIGN_IN_PATH = '/sign-in'

// One engine per step, started while the step is on screen, so the long-pause
// timer runs on every step and content from one step doesn't follow the user
// to the next (R9).
function StepSupport({ children }: { children: ReactNode }) {
  const [engine] = useState(() => createTriggerEngine())

  useEffect(() => {
    engine.start()
    return () => engine.stop()
  }, [engine])

  return (
    <TriggerEngineContext.Provider value={engine}>
      {children}
      <SupportiveContent engine={engine} />
    </TriggerEngineContext.Provider>
  )
}

// Every onboarding step needs a signed-in user. Nothing renders until the
// Supabase session is known, and all auth navigation replaces the history
// entry so Back never returns to a page the user can't see.
export default function OnboardingLayout({
  children,
}: {
  children: ReactNode
}) {
  const router = useRouter()
  const pathname = usePathname()
  const step = stepFromPath(pathname)
  const [signedIn, setSignedIn] = useState(false)

  const toSignIn = useCallback(() => router.replace(SIGN_IN_PATH), [router])

  useEffect(() => {
    let current = true
    void getAccessToken().then((token) => {
      if (!current) return
      if (token) setSignedIn(true)
      else toSignIn()
    })
    return () => {
      current = false
    }
  }, [toSignIn])

  // Leaves for sign-in even if Supabase can't be reached; the local session
  // is cleared either way.
  async function signOut() {
    try {
      await getSupabaseClient().auth.signOut()
    } finally {
      toSignIn()
    }
  }

  if (!signedIn) return null

  return (
    <UnauthorizedContext.Provider value={toSignIn}>
      <AppShell currentStep={step} onSignOut={() => void signOut()}>
        <StepSupport key={step ?? pathname}>{children}</StepSupport>
      </AppShell>
    </UnauthorizedContext.Provider>
  )
}
