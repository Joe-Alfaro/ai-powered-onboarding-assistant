'use client'

import { useApiClient } from '@/api/useApiClient'
import { getSupabaseClient } from '@/auth/supabase'
import { PrivacyControls } from '@/privacy/PrivacyControls'

// Outside the step list, so it is reachable at any point (R13).
export default function PrivacyPage() {
  const api = useApiClient()

  // The account is gone, so the session is too; the result message stays.
  function signOut() {
    void getSupabaseClient().auth.signOut()
  }

  return (
    <>
      <h1>Privacy and your data</h1>
      <p>
        You can withdraw your consent, or remove everything we hold about you,
        at any time.
      </p>
      <PrivacyControls api={api} onDeleted={signOut} />
    </>
  )
}
