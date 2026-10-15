import { createClient } from '@supabase/supabase-js'
import {
  mockSupabase,
  NO_SESSION,
  resetMockSupabase,
  sessionFor,
} from '@/test-utils/supabase'
import { getAccessToken, getSupabaseClient } from './supabase'

jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const SUPABASE_URL = 'https://project.example.test'
const ANON_KEY = 'anon-key-for-tests'

describe('Supabase auth (sign-in only)', () => {
  beforeAll(() => {
    // Read when the client is first created, not at import time.
    process.env.NEXT_PUBLIC_SUPABASE_URL = SUPABASE_URL
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = ANON_KEY
  })

  beforeEach(() => {
    resetMockSupabase()
    jest
      .mocked(createClient)
      .mockReturnValue(
        mockSupabase as unknown as ReturnType<typeof createClient>,
      )
  })

  it('creates one client from the public URL and anon key', () => {
    const first = getSupabaseClient()
    const second = getSupabaseClient()

    expect(first).toBe(second)
    expect(createClient).toHaveBeenCalledTimes(1)
    expect(jest.mocked(createClient).mock.calls[0].slice(0, 2)).toEqual([
      SUPABASE_URL,
      ANON_KEY,
    ])
  })

  it("returns the current session's access token", async () => {
    mockSupabase.auth.getSession.mockResolvedValue(
      sessionFor('user-uuid-123', 'jwt-from-session'),
    )

    await expect(getAccessToken()).resolves.toBe('jwt-from-session')
  })

  it('returns null when nobody is signed in', async () => {
    mockSupabase.auth.getSession.mockResolvedValue(NO_SESSION)

    await expect(getAccessToken()).resolves.toBeNull()
  })

  it('returns null when the session lookup fails', async () => {
    mockSupabase.auth.getSession.mockResolvedValue({
      data: { session: null },
      error: new Error('auth unreachable'),
    })

    await expect(getAccessToken()).resolves.toBeNull()
  })

  it('never reads tables or storage from the browser', async () => {
    mockSupabase.auth.getSession.mockResolvedValue(
      sessionFor('user-uuid-123', 'jwt-from-session'),
    )

    await getAccessToken()

    expect(mockSupabase.from).not.toHaveBeenCalled()
    expect(mockSupabase.storage.from).not.toHaveBeenCalled()
  })
})
