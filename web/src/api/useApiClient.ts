'use client'

import { useState } from 'react'
import { getAccessToken } from '@/auth/supabase'
import { createApiClient } from './client'

// The API client a page uses: the configured base URL and the signed-in
// user's Supabase token.
export function useApiClient() {
  const [api] = useState(() =>
    createApiClient({
      baseUrl: process.env.NEXT_PUBLIC_API_URL ?? '',
      getAccessToken,
    }),
  )
  return api
}
