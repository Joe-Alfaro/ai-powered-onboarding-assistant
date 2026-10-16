'use client'

import { createContext, useContext } from 'react'

// What the API client does on a 401. The onboarding layout sends the user
// back to sign in; outside it, pages handle the error themselves.
export const UnauthorizedContext = createContext<(() => void) | null>(null)

export function useOnUnauthorized() {
  return useContext(UnauthorizedContext)
}
