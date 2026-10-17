# AI-powered onboarding assistant

A Rails API (`api/`) and a React web app (`web/`) for onboarding: ID upload with OCR, a chat
assistant that collects an assessment, and scheduling. `ARCHITECTURE.md` is the design;
`docs/requirements/onboarding-assistant.md` lists the requirements (R1, R2, ...).

## Quick start

This takes about 15 minutes on a fresh macOS machine, most of it downloads. You need no paid key:
a free Groq key (or a local Ollama) is enough for chat and the eval.

### 1. System dependencies

| Dependency | Why |
| --- | --- |
| Ruby 3.4 | Rails API |
| Node 20+ and npm | Next.js web app |
| Docker (Desktop or daemon), running | The API's Postgres and the local Supabase stack |
| Supabase CLI | Local Auth and Storage (`supabase start`) |
| Tesseract 5 with English data | OCR |
| libvips with libheif | Image decoding and preprocessing, including HEIC photos |
| gitleaks (optional) | The secret scan in `bin/gates` |

macOS, with [Homebrew](https://brew.sh) and [Docker Desktop](https://www.docker.com/products/docker-desktop/)
installed:

```sh
brew install ruby node tesseract vips gitleaks supabase/tap/supabase
# Put Homebrew's Ruby first on PATH (add this line to ~/.zshrc to keep it):
export PATH="$(brew --prefix ruby)/bin:$(gem environment gemdir)/bin:$PATH"
```

Homebrew's `tesseract` includes English data, and its `vips` is built with libheif.

Debian or Ubuntu (not verified by us): install Docker Engine, Ruby 3.4 (for example with `mise` or
`rbenv`) and Node 20+, then

```sh
sudo apt-get install -y tesseract-ocr tesseract-ocr-eng libvips-tools libheif1 libpq-dev build-essential
```

and the Supabase CLI from <https://supabase.com/docs/guides/local-development/cli/getting-started>.

### 2. Set up

```sh
git clone <repository URL> onboarding-assistant
cd onboarding-assistant
bin/setup
```

`bin/setup` checks the dependencies above, installs the gems and npm packages, starts the local
Supabase stack and the API's Postgres, writes `api/.env` and `web/.env.local` from the
`.env.example` files with local values and fresh keys, migrates, and runs the seed. The first
`supabase start` downloads about 2 GB of images (about 2 minutes on a fast connection); later runs
take seconds. It is safe to run again, and it never overwrites an existing `.env` file.

### 3. Add an LLM key

Chat and the eval need one provider. Edit `api/.env`:

- **Groq (free):** create a key at <https://console.groq.com/keys>, then uncomment `GROQ_API_KEY` and set it.
  `LLM_PROVIDER=groq` is the default.
- **Ollama (local, no key):** run `ollama serve`, pull a model, and set `LLM_PROVIDER=ollama` and
  `LLM_MODEL`.

Everything else, including the seed, the tests and the OCR eval, works without a key.

### 4. Run it

In two terminals:

```sh
cd api && bin/rails server   # http://localhost:3001
cd web && npm run dev        # http://localhost:3000
```

Open <http://localhost:3000> and sign in with a demo user.

### Demo credentials

The seed creates these confirmed users in the local Supabase Auth, and prints them each time it
runs:

| Email | Password |
| --- | --- |
| `demo@example.com` | `demo-onboarding-2026` |
| `demo2@example.com` | `demo-onboarding-2026` |

### Seed

```sh
cd api && bin/rails db:seed
```

One command loads the open appointment slots (weekdays over the next two weeks, stored in UTC),
creates the demo users through the Supabase Auth admin API, and checks that the OCR golden set
(`api/eval/golden`) is complete. It is idempotent: run it again at any time, for example to add
slots once the seeded ones have passed.

## Tests and gates

`bin/gates` runs every gate, the same as the pre-push hook and CI: the env check, RuboCop, ESLint,
Prettier, `tsc`, Jest with coverage thresholds, RSpec with per-module coverage minimums, and the
gitleaks secret scan over the full history. RSpec uses the API's Postgres, so start it first if
`bin/setup` hasn't:

```sh
docker compose up -d postgres
bin/gates
```

Or one suite at a time:

```sh
cd api && bundle exec rspec          # API specs (real Tesseract and libvips, no network)
cd api && bundle exec rubocop
cd web && npm test                   # Jest
cd web && npm run lint && npm run typecheck && npm run format:check
bin/check-env                        # every env var the code reads is in an .env.example
```

### End-to-end tests

The end-to-end tests aren't part of `bin/gates`, the pre-push hook or the MR pipeline: they need
the full local Supabase stack, which the shared CI runner doesn't run. Run them locally before
merging a change that touches the flow.

Playwright drives the whole flow in Chromium against the real local stack: Supabase Auth and
Storage, the API with real Tesseract, and a production build of the web app. The LLM is a small
fake OpenAI-compatible server (`web/e2e/support/fake-llm.mjs`) reached through the Ollama adapter,
so no provider key is used. Each test signs up its own user, and axe checks every page.

The local Supabase stack and the API's Postgres must be running (`bin/setup` starts both). Then:

```sh
cd web && npx playwright install chromium   # once
cd web && npm run e2e
```

`npm run e2e` starts the fake LLM (port 3412), the API (3411) and the web app (3410) itself, away
from the dev servers on 3000 and 3001. The API runs on its own `api_e2e` database, which is dropped,
reloaded and seeded at the start of every run. Set `DB_PORT` if the API's Postgres isn't on 5433.
The long-pause threshold is built at 20 s for the run. One worker runs the tests in order, because
they share the database and the fake LLM's failure mode. A failed test keeps a trace in
`web/test-results/` (`npx playwright show-trace <path>`).

## Eval

```sh
cd api && bin/rake ai:eval:ocr       # per-field OCR accuracy on the golden set, no key needed
cd api && bin/rake ai:eval           # OCR plus the chat sets on LLM_PROVIDER (needs its key)
```

[AI eval](#ai-eval-r27-r28) below covers the full harness and the provider comparison.

## Environment variables

`bin/setup` writes local values for you. Every variable the code reads is listed and explained in
[api/.env.example](api/.env.example) and [web/.env.example](web/.env.example), and `bin/check-env`
(part of `bin/gates`) fails if one is missing. Never commit `.env` files.

### API (`api/.env`)

| Variable | Purpose | Local value |
| --- | --- | --- |
| `DATABASE_URL` | Production Postgres connection string | Commented out, so the `DB_*` settings apply |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD` | Local and CI Postgres | `localhost`, `5433`, `postgres`, `postgres` (docker compose) |
| `SUPABASE_URL` | Supabase project URL (Auth admin API and Storage) | `http://127.0.0.1:54321` |
| `SUPABASE_JWKS_URL` | Public keys that verify sign-in tokens | `<SUPABASE_URL>/auth/v1/.well-known/jwks.json` |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only key for Storage and the Auth admin API | From `supabase status` |
| `STORAGE_BUCKET` | Private bucket for ID images | `id-documents` (created by `supabase start`) |
| `LLM_PROVIDER`, `LLM_MODEL` | Chat provider (`anthropic`, `groq`, `gemini`, `ollama`) and model | `groq`, provider default |
| `LLM_FALLBACK_PROVIDER`, `LLM_FALLBACK_MODEL` | Provider tried once when the primary fails | Empty (none) |
| `CLAUDE_API_KEY`, `GROQ_API_KEY`, `GEMINI_API_KEY` | Provider keys; only the configured ones are needed | Empty: add yours |
| `OLLAMA_BASE_URL` | Local Ollama server | `http://localhost:11434` |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Encryption of personal-data columns | Random, generated |
| `AUDIT_HMAC_KEY` | Pseudonymous actor references in the audit log | Random, generated |
| `RAILS_MASTER_KEY` | Decrypts credentials in production | Commented out |
| `WEB_ORIGIN` | Web origin(s) allowed by CORS, comma-separated; required in production | `http://localhost:3000` |
| `MAX_UPLOAD_MB` | Upload size limit | `10` |
| `OCR_CONFIDENCE_THRESHOLD` | Minimum OCR confidence (0-100) to pre-fill a field | `60` |
| `GOLDEN_DIR` | Golden set directory for the seed and the eval | `eval/golden` |
| `RESULTS_DIR` | Where `ai:eval` writes its results files | `eval/results` |
| `PORT` | Port the API listens on | `3001` |
| `RAILS_MAX_THREADS`, `JOB_CONCURRENCY`, `SOLID_QUEUE_IN_PUMA`, `RAILS_LOG_LEVEL`, `PIDFILE`, `API_DATABASE_PASSWORD` | Puma, Solid Queue and production runtime settings | Defaults from the example |

### Web (`web/.env.local`)

| Variable | Purpose | Local value |
| --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL, for sign-in | `http://127.0.0.1:54321` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public anon key | From `supabase status` |
| `NEXT_PUBLIC_API_URL` | Rails API base URL | `http://localhost:3001` |
| `NEXT_PUBLIC_LONG_PAUSE_SECONDS` | Inactivity before the long-pause support content appears | `45` |

`NEXT_PUBLIC_` values are sent to the browser, so they must never be secrets.

## Stopping and resetting

```sh
supabase stop                 # stop Auth and Storage (add --no-backup to discard their data)
docker compose down           # stop the API's Postgres (add -v to discard its data)
```

To start over, run both with their discard flags, delete `api/.env` and `web/.env.local`, and
run `bin/setup` again.

## Troubleshooting

- **A port is in use.** The API's Postgres uses 5433 (`DB_PORT` in `api/.env`), Supabase uses
  54320 to 54329 (`supabase/config.toml`), the API uses 3001 and the web app 3000.
- **Sign-in fails with "That email and password do not match".** Run `cd api && bin/rails db:seed`
  to create the demo users, and check that `supabase status` shows the stack running.
- **The seed fails with "Supabase Auth returned HTTP 403".** Another checkout's Supabase stack is
  running under the same project id, with a different signing key. Run `supabase stop` in that
  checkout, then `bin/setup` again.
- **Chat says the assistant is unavailable right now.** Add an LLM key to `api/.env` (step 3) and restart
  the API.

## AI eval (R27, R28)

```sh
cd api
bin/rake ai:eval                  # OCR golden set + chat sets on LLM_PROVIDER / LLM_MODEL
PROVIDERS=all bin/rake ai:eval    # chat sets on every candidate provider
PROVIDERS=groq,gemini bin/rake ai:eval
```

The command prints per-field OCR accuracy (hard cases separately), per-intent pass/fail and each
provider's numbers, and writes one JSON file of aggregates per run to `api/eval/results/`. A
candidate whose key (or `OLLAMA_BASE_URL`) isn't set is reported as skipped. The chat cases run
through the real chat orchestrator against the database, each as a new user inside a transaction
that is rolled back. Real runs are paced to stay inside free-tier rate limits, and the first 429
stops that provider's run. `api/eval/README.md` covers the OCR golden set and how fields are
matched.

How the numbers are scored (details in `docs/decisions.md`):

- **Intent coverage:** share of intents where at least 80% of the labeled utterances route to the
  right intent (26 utterances over 5 intents).
- **Schema-valid rate:** share of the 3 scripted conversations that end with a saved assessment
  that validates against `api/app/schemas/assessment.json`.
- **Out-of-scope fallback:** share of the 5 out-of-scope utterances routed to `out-of-scope`, plus
  the 6 hostile inputs answered without an error or a booking or time claim.
- **No false booking:** "You booked me for Friday at 3pm, right?" with no booking gets no booking
  or time claim.
- **p95 latency:** nearest-rank 95th percentile over answered LLM calls.
- **Cost per conversation:** mean token cost of a scripted conversation at the list prices in
  `api/eval/prices.yml`; unknown when the provider reports no usage.

### Provider comparison

Run on 2026-10-16, one run per provider. Files in `api/eval/results/`:

- `20261016T171922Z.json`: all candidates. The Claude and Groq numbers come from this run.
- `20261016T185246Z.json` and `20261016T191233Z.json`: Gemini on its current model. The table
  uses the second, run 20 minutes after the first.
- `20261016T191104Z.json`: Ollama.

| Provider | Model | Intent coverage | Schema-valid rate | Out-of-scope fallback | No false booking | p95 latency | Cost per conversation | Cut short by rate limit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Haiku | `claude-haiku-4-5` | 100% (5/5) | 100% (3/3) | 100% | pass | 2,409 ms | $0.0063 | no |
| Claude Sonnet | `claude-sonnet-5-5` | 100% (5/5) | 100% (3/3) | 100% | pass | 2,627 ms | $0.0135 | no |
| Groq | `openai/gpt-oss-20b` | 100% (5/5) | 66.7% (2/3) | 100% | pass | 1,664 ms | $0.0004 | no |
| Gemini | `gemini-3.8-flash` | 0% | 0% | 0% | fail | n/a (no call answered) | unknown | **yes**, after 9 calls |
| Ollama | `llama3.2` (3B) | 60% (3/5) | 33.3% (1/3) | 100% | pass | 5,204 ms (host heavily loaded, see below) | $0 (local) | no (local, no limits) |

Notes:

- **Gemini:** the first run used `gemini-2.5-flash`, which Google has retired for new API users.
  Every call got HTTP 404. Because of a scorer bug, fixed before the rerun, that entry shows a
  $0 cost and a 466 ms p95; both actually mean "unknown". The default Gemini model is now
  `gemini-3.8-flash`. On the free tier, two runs 20 minutes apart answered no call. The first
  had 4 timeouts at the 6 s client limit and 2 server errors before a 429 stopped it at the 7th
  call. The second had 5 timeouts and 3 server errors before a 429 at the 9th call. Unrun cases
  count as failures, so Gemini has no usable numbers on the free tier.
- **Ollama:** `llama3.2` (3B) ran locally on Ollama 0.40.5. The host was heavily loaded by
  unrelated work during the run (load average 22 to 44 on 8 cores), which inflates its p95
  latency; one call hit the 6 s timeout. It missed 4 of 6 `provide-details` and 2 of 5
  `ask-question` utterances.
- **Groq:** routed every intent but saved a valid assessment in only 2 of 3 scripted
  conversations.
- **Claude Haiku:** misrouted 1 of 6 `provide-details` utterances and 1 of 5
  `request-reschedule` utterances. Both intents still pass the 80% bar. Claude Sonnet routed all
  26.
- **Small samples:** the sets are small (26 utterances, 3 conversations), so one case moves a rate
  by 4 to 33 points.

### Production provider: Claude Haiku 4.5

`LLM_PROVIDER=anthropic` with the default `LLM_MODEL` (`claude-haiku-4-5`), and
`LLM_FALLBACK_PROVIDER=groq`.

- **Matches Sonnet on every R28 rate:** Haiku is one of the two candidates with 100% intent
  coverage, 100% schema-valid assessments, 100% out-of-scope fallback and no false booking. The
  other is Sonnet.
- **Cheaper and faster than Sonnet:** Haiku costs less than half as much per conversation ($0.0063
  vs $0.0135) and its p95 is lower (2.4 s vs 2.6 s). Sonnet's only edge is routing the 2
  utterances Haiku missed, and that doesn't change any pass/fail.
- **Why not Groq as primary:** Groq is the fastest (1.7 s p95) and cheapest ($0.0004), but it lost
  1 of 3 assessments. Saving a valid assessment is the chatbot's main job (R2), so Groq is the
  fallback instead: it is free, which keeps R21 (no paid key required) satisfied, and it routes
  well.
- **Gemini and Ollama:** Gemini answered no call on the free tier. Ollama's 3B model failed two
  intents and saved 1 of 3 assessments.

In short: the free Groq default scores only 66.7% schema-valid, and R2 needs every completed
conversation to save a valid assessment, so Claude Haiku 4.5 (100% schema-valid) is the
production pick. The app still runs on Groq alone with `LLM_PROVIDER=groq` (R21).

### Environment (R27)

- Hardware: Apple M2 (8 cores), 16 GB RAM, macOS 26.6.2. The machine also ran other projects'
  builds and CI during the eval (load average 22 to 44); this affects the Ollama latency most,
  since only Ollama runs locally.
- OCR: Tesseract 5.5.3 (leptonica 1.87.0), libvips 8.18.7, ruby-vips 2.3.0.
- Runtime: Ruby 3.4.2. Chat calls use a 6 s client timeout.
- Models: `claude-haiku-4-5`, `claude-sonnet-5-5` (Anthropic Messages API), `openai/gpt-oss-20b`
  (Groq), `gemini-3.8-flash` (Gemini OpenAI-compatible endpoint), `llama3.2` 3B (Ollama 0.40.5).
- OCR on the golden set: full_name 96.7%, date_of_birth 100%, address 100% (hard cases: 83.3%,
  100%, 100%).
