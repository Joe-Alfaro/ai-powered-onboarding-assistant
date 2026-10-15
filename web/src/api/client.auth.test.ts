import { createClient } from '@supabase/supabase-js'
import { getAccessToken } from '@/auth/supabase'
import { headerOf, installFetch, jsonResponse } from '@/test-utils/fetch'
import {
  mockSupabase,
  resetMockSupabase,
  sessionFor,
} from '@/test-utils/supabase'
import { createApiClient } from './client'

jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const USER_ID = 'user-uuid-5f3a9c'

describe('API client with Supabase sign-in (R19)', () => {
  let fetchMock: jest.Mock

  beforeAll(() => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
  })

  beforeEach(() => {
    resetMockSupabase()
    jest
      .mocked(createClient)
      .mockReturnValue(
        mockSupabase as unknown as ReturnType<typeof createClient>,
      )
    mockSupabase.auth.getSession.mockResolvedValue(
      sessionFor(USER_ID, 'session-jwt'),
    )
    fetchMock = installFetch()
    fetchMock.mockResolvedValue(jsonResponse(200, {}))
  })

  it("sends the session's access token and never the user ID", async () => {
    const api = createApiClient({
      baseUrl: 'https://api.example.test',
      getAccessToken,
    })

    await api.request('/bookings', { method: 'POST', body: { slot_id: 7 } })

    const [url, init] = fetchMock.mock.calls[0]
    expect(headerOf(init, 'Authorization')).toBe('Bearer session-jwt')
    const everythingSent = JSON.stringify([url, init, init.headers, init.body])
    expect(everythingSent).not.toContain(USER_ID)
  })
})
