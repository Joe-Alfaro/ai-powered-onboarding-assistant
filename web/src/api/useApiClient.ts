'use client'

import { useMemo } from 'react'
import { getAccessToken } from '@/auth/supabase'
import { createApiClient } from './client'
import { useOnUnauthorized } from './UnauthorizedContext'

// The API client a page uses: the configured base URL, the signed-in user's
// Supabase token and the surrounding layout's 401 handler. The layout keeps
// its handler stable, so the client is built once per page.
export function useApiClient() {
  const onUnauthorized = useOnUnauthorized()

  return useMemo(
    () =>
      createApiClient({
        baseUrl: process.env.NEXT_PUBLIC_API_URL ?? '',
        getAccessToken,
        onUnauthorized: onUnauthorized ?? undefined,
      }),
    [onUnauthorized],
  )
}
