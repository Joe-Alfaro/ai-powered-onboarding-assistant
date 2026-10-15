// A stand-in for the client returned by @supabase/supabase-js createClient.
// Tests mock the package so createClient returns this object. `from` and
// `storage` exist only so tests can assert the app never reads tables or
// storage from the browser.
export const mockSupabase = {
  auth: {
    getSession: jest.fn(),
    signInWithPassword: jest.fn(),
    signOut: jest.fn(),
  },
  from: jest.fn(),
  storage: { from: jest.fn() },
}

export function resetMockSupabase() {
  mockSupabase.auth.getSession.mockReset()
  mockSupabase.auth.signInWithPassword.mockReset()
  mockSupabase.auth.signOut.mockReset()
  mockSupabase.from.mockReset()
  mockSupabase.storage.from.mockReset()
}

export function sessionFor(userId: string, accessToken: string) {
  return {
    data: {
      session: {
        access_token: accessToken,
        refresh_token: 'refresh-token',
        user: { id: userId, email: 'demo@example.test' },
      },
    },
    error: null,
  }
}

export const NO_SESSION = { data: { session: null }, error: null }
