import { defineConfig, devices } from '@playwright/test'
import {
  API_URL,
  FAKE_LLM_URL,
  LONG_PAUSE_SECONDS,
  WEB_URL,
  supabaseLocal,
} from './e2e/support/stack'

// End-to-end tests against the real local stack: the local Supabase stack
// (Auth and Storage, started by hand with `supabase start`), the API's
// Postgres (docker compose), and the API, the web app and a fake LLM started
// here. One browser and one worker: the tests share one database and the fake
// LLM's failure mode, and the host is shared.
const supabase = supabaseLocal()
const dbPort = process.env.DB_PORT ?? '5433'
const fakeLlmPort = new URL(FAKE_LLM_URL).port
const apiPort = new URL(API_URL).port
const webPort = new URL(WEB_URL).port

// Fixed local-only keys, so the e2e database never depends on api/.env.
const LOCAL_KEY = 'e2e-local-only-key-0123456789abcdef0123456789abcdef'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  forbidOnly: !!process.env.CI,
  timeout: 90_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    baseURL: WEB_URL,
    trace: 'retain-on-failure',
    ...devices['Desktop Chrome'],
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: [
    {
      command: `node e2e/support/fake-llm.mjs ${fakeLlmPort}`,
      url: `${FAKE_LLM_URL}/__calls`,
      reuseExistingServer: false,
    },
    {
      command: 'e2e/support/start-api.sh',
      url: `${API_URL}/up`,
      reuseExistingServer: false,
      timeout: 180_000,
      env: {
        RAILS_ENV: 'development',
        PORT: apiPort,
        DATABASE_URL: `postgres://postgres:postgres@localhost:${dbPort}/api_e2e`,
        SUPABASE_URL: supabase.url,
        SUPABASE_JWKS_URL: `${supabase.url}/auth/v1/.well-known/jwks.json`,
        SUPABASE_SERVICE_ROLE_KEY: supabase.serviceRoleKey,
        STORAGE_BUCKET: 'id-documents',
        // The fake LLM, through the OpenAI-compatible Ollama adapter. Real
        // provider keys are set empty so a local api/.env can't supply them.
        LLM_PROVIDER: 'ollama',
        LLM_MODEL: 'fake',
        OLLAMA_BASE_URL: FAKE_LLM_URL,
        LLM_FALLBACK_PROVIDER: '',
        CLAUDE_API_KEY: '',
        GROQ_API_KEY: '',
        GEMINI_API_KEY: '',
        ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY: LOCAL_KEY,
        ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY: `${LOCAL_KEY}-det`,
        ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT: `${LOCAL_KEY}-salt`,
        AUDIT_HMAC_KEY: `${LOCAL_KEY}-audit`,
        WEB_ORIGIN: WEB_URL,
        MAX_UPLOAD_MB: '10',
        OCR_CONFIDENCE_THRESHOLD: '60',
        GOLDEN_DIR: 'eval/golden',
      },
    },
    {
      // A production build, so no dev overlay stands in for the app's own
      // error pages (R30).
      command: `npm run build && npx next start -H 127.0.0.1 -p ${webPort}`,
      url: WEB_URL,
      reuseExistingServer: false,
      timeout: 300_000,
      env: {
        NEXT_PUBLIC_SUPABASE_URL: supabase.url,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: supabase.anonKey,
        NEXT_PUBLIC_API_URL: API_URL,
        NEXT_PUBLIC_LONG_PAUSE_SECONDS: String(LONG_PAUSE_SECONDS),
        NEXT_PUBLIC_MAX_UPLOAD_MB: '10',
      },
    },
  ],
})
