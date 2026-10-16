// Shared setup for the flow tests: sign-in, the auth guard, sign-out, the
// home redirect and the done page. The App Router hooks are mocked, Supabase
// is mocked at its package, and the API is reached only through fetch.
import { createClient } from '@supabase/supabase-js'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { jsonResponse, type FakeResponse } from './fetch'
import { mockSupabase, resetMockSupabase, sessionFor } from './supabase'

export const API_URL = 'https://api.example.test'
export const TOKEN = 'session-jwt-for-flow-tests'

export const router = {
  push: jest.fn(),
  replace: jest.fn(),
  back: jest.fn(),
  forward: jest.fn(),
  refresh: jest.fn(),
  prefetch: jest.fn(),
}

// Tests that use this must mock both packages first:
//   jest.mock('next/navigation', () => ({ useRouter: jest.fn(),
//     usePathname: jest.fn(), useSearchParams: jest.fn() }))
//   jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))
export function setUpFlow({
  pathname = '/',
  signedIn = true,
}: { pathname?: string; signedIn?: boolean } = {}) {
  process.env.NEXT_PUBLIC_API_URL = API_URL
  process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
  Object.values(router).forEach((fn) => fn.mockReset())
  jest
    .mocked(useRouter)
    .mockReturnValue(router as unknown as ReturnType<typeof useRouter>)
  jest.mocked(usePathname).mockReturnValue(pathname)
  jest
    .mocked(useSearchParams)
    .mockReturnValue(
      new URLSearchParams() as unknown as ReturnType<typeof useSearchParams>,
    )
  resetMockSupabase()
  jest
    .mocked(createClient)
    .mockReturnValue(mockSupabase as unknown as ReturnType<typeof createClient>)
  setSignedIn(signedIn)
  mockSupabase.auth.signOut.mockImplementation(async () => {
    setSignedIn(false)
    return { error: null }
  })
}

export function setSignedIn(signedIn: boolean) {
  mockSupabase.auth.getSession.mockResolvedValue(
    signedIn
      ? sessionFor('user-uuid-flow', TOKEN)
      : { data: { session: null }, error: null },
  )
}

type Route = FakeResponse | (() => FakeResponse | Promise<FakeResponse>)

// Answers each "METHOD /path" with its response. Anything else is a 404
// envelope, so a request the test didn't expect is visible as a failure.
export function routeApi(fetchMock: jest.Mock, routes: Record<string, Route>) {
  fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
    const key = `${init?.method ?? 'GET'} ${url.replace(API_URL, '')}`
    const route = routes[key]
    if (!route) {
      return jsonResponse(404, {
        error: { code: 'not_found', message: 'No route', actions: [] },
      })
    }
    return typeof route === 'function' ? route() : route
  })
}

export function requestsMade(fetchMock: jest.Mock) {
  return fetchMock.mock.calls.map(
    ([url, init]: [string, RequestInit | undefined]) =>
      `${init?.method ?? 'GET'} ${url.replace(API_URL, '')}`,
  )
}

export const ASSESSMENT = {
  reason: 'Ongoing support after a recent move',
  urgency: 'soon',
  preferred_window: 'weekday mornings',
  distress: false,
  notes: 'Prefers video calls',
}

export interface OnboardingState {
  step?: string
  assessment?: typeof ASSESSMENT | null
  identity?: {
    confirmed: boolean
    source: 'ocr' | 'manual' | null
    confirmed_at: string | null
  }
}

// The 200 body of GET /onboarding: where the user is in the flow and what
// they have finished. Identity is a status only; its values never come back.
export function onboardingResponse({
  step = 'chat',
  assessment = null,
  identity = { confirmed: false, source: null, confirmed_at: null },
}: OnboardingState = {}) {
  return jsonResponse(200, { onboarding: { step, assessment, identity } })
}

export const BOOKING = {
  id: 'booking-uuid-1',
  status: 'active',
  // 10:00 AM in New York, where Jest runs (EST: DST ended on Nov 1, 2026).
  slot: {
    id: 'slot-uuid-1',
    starts_at: '2026-11-03T15:00:00Z',
    ends_at: '2026-11-03T15:30:00Z',
  },
}

export function bookingsResponse(bookings: (typeof BOOKING)[] = []) {
  return jsonResponse(200, { bookings })
}
