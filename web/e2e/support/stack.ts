import { execFileSync } from 'node:child_process'
import path from 'node:path'

// Where the end-to-end stack runs. Ports are fixed and away from the dev
// servers (3000, 3001) so the tests can run beside them.
export const WEB_URL = 'http://127.0.0.1:3410'
export const API_URL = 'http://127.0.0.1:3411'
export const FAKE_LLM_URL = 'http://127.0.0.1:3412'

// Short, so the long-pause test needn't wait 45 s, and long enough that the
// happy path never idles that long on one step.
export const LONG_PAUSE_SECONDS = 20

export const REPO_ROOT = path.resolve(__dirname, '../../..')

export interface SupabaseLocal {
  url: string
  anonKey: string
  serviceRoleKey: string
}

// The local Supabase stack's URL and keys, read once from the CLI and passed
// to the test workers through the environment. These are the CLI's local
// development keys, not secrets.
export function supabaseLocal(): SupabaseLocal {
  if (!process.env.E2E_SUPABASE_URL) {
    let raw: string
    try {
      raw = execFileSync('supabase', ['status', '-o', 'json'], {
        cwd: REPO_ROOT,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      })
    } catch {
      throw new Error(
        'The local Supabase stack is not running. Start it with `supabase start` (see README.md).',
      )
    }
    const status = JSON.parse(raw) as Record<string, string>
    process.env.E2E_SUPABASE_URL = status.API_URL
    process.env.E2E_SUPABASE_ANON_KEY = status.ANON_KEY
    process.env.E2E_SUPABASE_SERVICE_ROLE_KEY = status.SERVICE_ROLE_KEY
  }
  return {
    url: process.env.E2E_SUPABASE_URL ?? '',
    anonKey: process.env.E2E_SUPABASE_ANON_KEY ?? '',
    serviceRoleKey: process.env.E2E_SUPABASE_SERVICE_ROLE_KEY ?? '',
  }
}
