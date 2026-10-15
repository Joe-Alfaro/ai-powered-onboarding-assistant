import { createClient, type SupabaseClient } from '@supabase/supabase-js'

// The browser uses Supabase for sign-in only. All data goes through the API,
// so nothing here reads tables or storage (R19).
let client: SupabaseClient | null = null

// Created on first use, not at import, so the public variables are read when
// the app (or a test) has set them.
export function getSupabaseClient() {
  if (!client) {
    client = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
    )
  }
  return client
}

// The current session's access token, or null when signed out or when the
// session can't be read.
export async function getAccessToken() {
  try {
    const { data, error } = await getSupabaseClient().auth.getSession()
    if (error) return null
    return data.session?.access_token ?? null
  } catch {
    return null
  }
}
