// Shared setup for page tests: the App Router hooks, a signed-in Supabase
// session and the API base URL. Pages build their own API client, so these
// tests reach the API only through fetch.
import { createClient } from '@supabase/supabase-js'
import { useRouter, useSearchParams } from 'next/navigation'
import { API_BASE } from './documents'
import { mockSupabase, resetMockSupabase, sessionFor } from './supabase'

export const router = {
  push: jest.fn(),
  replace: jest.fn(),
  back: jest.fn(),
  forward: jest.fn(),
  refresh: jest.fn(),
  prefetch: jest.fn(),
}

export function setUpPage(search = '') {
  process.env.NEXT_PUBLIC_API_URL = API_BASE
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
  Object.values(router).forEach((fn) => fn.mockReset())
  jest
    .mocked(useRouter)
    .mockReturnValue(router as unknown as ReturnType<typeof useRouter>)
  jest
    .mocked(useSearchParams)
    .mockReturnValue(
      new URLSearchParams(search) as unknown as ReturnType<
        typeof useSearchParams
      >,
    )
  resetMockSupabase()
  jest
    .mocked(createClient)
    .mockReturnValue(mockSupabase as unknown as ReturnType<typeof createClient>)
  mockSupabase.auth.getSession.mockResolvedValue(
    sessionFor('user-uuid-5f3a9c', 'session-jwt'),
  )
  mockSupabase.auth.signOut.mockResolvedValue({ error: null })
}
