# Performance (R22, R23, R24, R25, R38)

Three measurements, all run against a base URL so the same commands work on the local stack and
on the deployed API:

| Requirement | Tool | What it measures | Target |
| --- | --- | --- | --- |
| R22, R38 | `perf/load.js` (k6) | 20 virtual users for 60 s on the chatbot and the main API calls | p95 < 3.0 s, error rate near 0, 429s counted |
| R23 | `bin/rake perf:ocr` | 20 golden-set uploads, upload receipt to the extracted-fields response | p95 < 8.0 s |
| R24 | `bin/rake perf:booking` | 20 bookings, server time from each request's Lograge line | p95 < 1.0 s |

The two sections below hold the results: a **local baseline**, and the **deployed results**, which
are the ones R22 to R24 and R38 are judged on.

## Method

### Percentiles

Every p95 is a nearest-rank percentile: the smallest sample with at least 95% of samples at or
below it. With 20 runs that is the 19th fastest, so one slow run out of 20 doesn't move the p95
but two do. k6 reports its own p95 for the load test (it interpolates between samples); the rake
tasks use `Perf::Stats` (`api/lib/perf/stats.rb`, covered by `api/spec/lib/perf/stats_spec.rb`),
the same method as the eval harness. The timing tasks only time successful requests and report
failures separately as a count and an error rate.

### Load-test users and tokens

The k6 run and the timing tasks sign in as load-test users, one per virtual user. No token or
password is committed:

```sh
cd api
PERF_USER_PASSWORD='<a strong password you keep>' bin/rake perf:users
```

This creates `load-test-01@example.com` to `load-test-20@example.com` (`PERF_USERS` sets how many)
as confirmed users through the Supabase Auth admin API, signs each in with the password grant, and
writes the access tokens to `api/tmp/perf-tokens.json` (untracked, mode 600; `PERF_TOKENS_FILE`
moves it). It reads `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (and `SUPABASE_ANON_KEY` if set),
so for the deployed run point them at the production Supabase project. The users are reused on a
rerun, so use the same password each time. Tokens last for the project's JWT expiry (an hour by
default): run it just before measuring.

### R22: k6 load test

```sh
k6 run -e BASE_URL=<API URL> -e LLM_MODE=real -e SUMMARY_FILE=/tmp/k6.json perf/load.js
```

Each virtual user loops: `GET /health`, `GET /slots`, `GET /onboarding`, `POST /chat/messages`,
then `POST /bookings` on a random open slot and `DELETE /bookings/:id` to cancel what it holds, then sleeps
1 s. The report gives the overall p95, the p95 and median per endpoint, the error rate, and two
separate counts for R38: HTTP 429 responses from any endpoint, and chat replies that failed with
`llm_rate_limited` (the provider's 429 after the fallback provider was tried). A provider 429 that
the fallback answers is invisible to the client, so it shows up in neither count.

Expected statuses are 2xx, plus a 409 on `POST /bookings` when another virtual user took the slot
first or the user still holds a booking. Anything else counts as an error.

`LLM_MODE` is required and recorded in the output, so a result always says what the chat path hit:

- `real`: the API's configured provider. The only honest value for the deployed run.
- `fake`: the deterministic fake LLM from the end-to-end tests, through the Ollama adapter.
  `perf/local-api.sh` starts the API this way with `LLM_MODE=fake`, and with
  `LLM_MODE=real` uses the provider in `api/.env`.
- `off`: no chat requests, to measure the rest of the API alone.

The k6 flag records the mode; the API's own configuration decides it. `VUS` and `DURATION`
override 20 and `60s` for a smoke run.

### R23: OCR timing

```sh
cd api
PERF_BASE_URL=<API URL> PERF_LOG_FILE=<copy of the API log> bin/rake perf:ocr
```

The first load-test user grants consent, then uploads the first 20 images of `api/eval/golden`
(in `labels.json` order) one at a time to `POST /documents`. That request stores the image, runs
OCR and answers with the extracted fields, so its time is the upload-receipt-to-fields time.

- **Client-side:** measured on a monotonic clock from just before the request is written to the
  end of the response, on an already-open connection, so it includes the upload transfer but
  not DNS, TCP or TLS setup.
- **Server-side:** the Lograge `duration` of the same request, matched by its `X-Request-Id`, when
  `PERF_LOG_FILE` is given. Locally that's `api/log/perf-server.log` (written by
  `perf/local-api.sh`); on the deployed service save the log for the run's time window to a file.

A run counts as successful only when it answers 200 with the fields. The uploads stay pending and
the purge job removes them with the rest.

### R24: booking timing

```sh
cd api
PERF_BASE_URL=<API URL> PERF_LOG_FILE=<copy of the API log> bin/rake perf:booking
```

The second load-test user cancels any booking it holds, then 20 times books the first open slot
and cancels it again. Only the `POST /bookings` requests are reported. The R24 number is the
server-side time, from each request's Lograge `duration` (R24 check 1), matched by request ID;
the client-side time is printed beside it. A run counts only on a 201.

## LOCAL BASELINE

> **Local only.** These numbers come from a development laptop under unrelated load, in Rails
> development mode, with the fake LLM. They show the tooling works and give a floor to compare
> against. They don't satisfy R22 to R24 or R38, which need the deployed run below.

Measured 2026-10-17 between 08:18 and 08:20 UTC.

**Setup**

- Hardware: Apple M2 (8 cores), 16 GB RAM, macOS 26.6.2.
- Host load: load average 15 to 23 on 8 cores during the runs (other projects' builds, CI and
  containers on the same machine), so the host was oversubscribed.
- Stack: the local Supabase stack (Auth and Storage on port 54321), the API's Postgres 17 in
  Docker, and the API from `perf/local-api.sh`: Rails development mode, one Puma process with 3
  threads (`RAILS_MAX_THREADS` default), Ruby 3.4.2, Tesseract 5.5.3. k6 2.3.0 on the same host.
  The web app isn't on any measured path (k6 and the tasks call the API directly).
- **LLM: not the real LLM.** The chat path hit the fake LLM (`LLM_MODE=fake`), which answers in a
  few milliseconds, so the chat numbers exclude provider latency (2.4 s p95 for Claude Haiku in
  the eval, see the README).

**R22, k6 (20 VUs, 60 s, `LLM_MODE=fake`)**

| Endpoint | p95 | Median |
| --- | --- | --- |
| All requests | 546 ms | |
| `GET /health` | 524 ms | 214 ms |
| `GET /slots` | 557 ms | 234 ms |
| `GET /onboarding` | 542 ms | 228 ms |
| `POST /chat/messages` | 560 ms | 250 ms |
| `POST /bookings` | 562 ms | 240 ms |
| `DELETE /bookings/:id` | 533 ms | 229 ms |

2,950 requests, error rate 0.00%, HTTP 429 responses 0, LLM rate-limited chat replies 0. The
endpoints all sit near the same p95, which points at queuing for the 3 Puma threads on a loaded
host rather than at any one endpoint.

**R23, OCR (20 uploads)**

| Measure | p50 | p95 | Max |
| --- | --- | --- | --- |
| Server-side (Lograge) | 1,021 ms | 1,563 ms | 2,104 ms |
| Client-side | 1,027 ms | 1,570 ms | 2,111 ms |

20 of 20 answered 200 with the extracted fields.

**R24, booking (20 bookings)**

| Measure | p50 | p95 | Max |
| --- | --- | --- | --- |
| Server-side (Lograge `duration`, the R24 number) | 12.9 ms | 27.4 ms | 39.0 ms |
| Client-side | 17.9 ms | 35.5 ms | 45.7 ms |

20 of 20 answered 201.

## Deployed results

> **Deployed, real LLM.** The first deployed run, the baseline for R18, R23, R24, R31 and R38. Its
> R22 result **missed the target** (chat client-side p95 11.5 s, overall 8.0 s, against 3.0 s) with
> Puma on 3 threads; the rerun under "After concurrency tuning" below replaces it and meets it.

Measured 2026-10-18: the smoke test from 19:57 UTC, the load and timing runs from 20:00:51 to
20:03:42 UTC, the chat re-check at 20:22 UTC and the cold start at 21:41:46 UTC.

**Setup**

- API: `https://api-production-460eb.up.railway.app`, web:
  `https://web-production-3d133.up.railway.app`. Railway, region `sfo` (US West), one replica per
  service. The plan isn't shown by the Railway CLI.
- API process: Rails 8.1 production mode, Ruby 3.4.2 with YJIT, **one Puma process with 3
  threads** (`RAILS_MAX_THREADS=3`), Solid Queue running inside Puma. Database, Auth and Storage on
  the hosted Supabase project, reached through the session pooler.
- **LLM: the real LLM.** Claude Haiku 4.5 (`LLM_PROVIDER=anthropic`, `LLM_MODEL=claude-haiku-4-5`),
  with the Groq fallback provider set.
- Code: the k6, OCR and booking runs hit the API built from `e03b573`, before the chat routing
  fix in `80ca414` (deployed 20:21 UTC). The tuned R22 rerun below runs on code that includes it.
- Client: k6 2.3.0 and the rake tasks on an Apple M2 laptop (16 GB) on a home connection in the
  US; requests entered Railway at its Atlanta edge (`x-railway-edge: atl1`), so every client-side
  time includes a cross-country round trip.
- Load-test users: `load-test-01@example.com` to `load-test-20@example.com`, created in the
  production Supabase project with `railway run --service api bin/rails perf:users` (tokens in an
  untracked file outside the repository). The tooling has no task to delete them, so they remain.

**R22, first run: k6 (20 VUs, 60 s, `LLM_MODE=real`), client-side**

| Endpoint | p95 | Median |
| --- | --- | --- |
| All requests | 8,025 ms | |
| `GET /health` | 8,309 ms | 2,307 ms |
| `GET /slots` | 2,277 ms | 831 ms |
| `GET /onboarding` | 2,311 ms | 830 ms |
| `POST /chat/messages` | 11,510 ms | 4,209 ms |
| `POST /bookings` | 8,808 ms | 2,562 ms |
| `DELETE /bookings/:id` | 4,410 ms | 910 ms |

Requests: 505, error rate: 0.00%, HTTP 429 responses: 0, LLM rate-limited chat replies: 0. Five
`POST /bookings` answered the expected 409 (another user took the slot first).

**Server-side for the same run.** The Lograge `duration` of each request in the run's window
(`railway logs --service api --json`; `GET /health` isn't logged), nearest-rank.

| Endpoint | Requests | p95 | Median |
| --- | --- | --- | --- |
| All logged requests | 420 | 1,982 ms | |
| `GET /slots` | 85 | 32 ms | 29 ms |
| `GET /onboarding` | 85 | 83 ms | 80 ms |
| `POST /chat/messages` | 85 | 3,538 ms | 1,832 ms |
| `POST /bookings` | 85 | 168 ms | 158 ms |
| `DELETE /bookings/:id` | 80 | 140 ms | 133 ms |

**Why the first run missed R22.** The server spends little time on anything but chat; the client-side times are
mostly queueing. Each chat request holds one of the 3 Puma threads for about 2 s (median) while it
waits on the LLM, so with 20 virtual users the requests behind it, `/health` included, wait for a
free thread. Even with no queue, the chat path's server p95 (3.5 s) is above 3 s on its own. The
rerun below, with 24 Puma threads, removes the queueing.

**R23, OCR (20 uploads of the golden set):** server-side p95 **1,838 ms** (p50 1,584 ms, max
1,854 ms); client-side p95 2,026 ms (p50 1,741 ms, max 2,036 ms), from the laptop above. 20 of 20
answered 200 with the extracted fields. Method: `bin/rails perf:ocr` with `PERF_BASE_URL` set to
the API, timing `POST /documents` (it stores the image, runs OCR and answers with the fields) on
the client; the server-side number is the Lograge `duration` of the 20 `POST /documents` requests
in the run's window, read from `railway logs --service api --json`. Target 8.0 s: met.

**R24, booking (20 bookings):** server-side p95 **156 ms** (p50 153 ms, max 157 ms), the Lograge
`duration` of the 20 `POST /bookings` requests in the run's window, read the same way; client-side
p95 260 ms. 20 of 20 answered 201. Method: `bin/rails perf:booking` with `PERF_BASE_URL`. Target
1.0 s: met.

**R38**

- The k6 run above targets the deployed URL.
- LLM 429s under load: none reached the client (0 HTTP 429 responses, 0 `llm_rate_limited`
  replies). A provider 429 answered by the fallback provider isn't visible to the client.
- First request after 30 minutes idle: the API's last logged request before it was at 20:45:28
  UTC (the tuned R22 run below), so it had been idle about 56 minutes (`GET /health` isn't logged,
  so an external uptime ping in that window can't be ruled out). Railway doesn't sleep services.
  Measured with `curl` from the laptop above at 21:41:46 UTC, on the tuned deployment (24
  threads): `GET /health` on the API answered 200 with a time to first byte of **1.50 s**
  (connect 0.09 s, TLS done at 0.13 s), and `GET /` on the web 200 in **0.26 s**. The next
  requests took 0.25 s and 0.18 s. Target 3 s: met.

**R18, HTTPS.** Checked with `curl` on 2026-10-18. Plain HTTP on both services answers `301 Moved
Permanently` to the same path over HTTPS (Railway's edge). The API sends
`Strict-Transport-Security: max-age=63072000; includeSubDomains`; the web service sends no HSTS
header, so a browser's first visit by plain HTTP still goes through the redirect.

**R31, log format.** The API writes each Lograge request line as single-line JSON; `railway logs
--json` returns it as a flat object with typed fields (`"duration": 158.2`), while the CLI's
default view only renders those fields as `key=value`. Every number above labelled server-side
comes from those fields.

**Browser smoke test of the deployed app.** Headless Chromium (Playwright, time zone
`America/Chicago`) against the web URL with a demo user and the real LLM: sign in; chat until the
assessment completes; consent, unticked by default; upload `api/eval/golden/001_clean.png`; the
OCR pre-filled the name, then confirm; book a slot shown in local time with a zone label (`Mon,
Oct 19, 2026, 9:00 AM CDT`); the done page.

- 19:57 UTC, on `e03b573`: every step passed, but the chat answered the first six on-topic
  messages with the out-of-scope template and saved the assessment's reason as `<UNKNOWN>`.
- 20:22 UTC, re-check on `80ca414` (the chat routing fix), same messages: **every step passed**.
  The chat asked real follow-ups and completed in 3 turns with no out-of-scope reply; the reason
  (`Help relocating pottery studio to a new building`) showed on the chat summary and the done
  page. The booking was then cancelled.

### After concurrency tuning

> **Deployed, real LLM.** This is the R22 rerun after the change that lets Puma threads
> outnumber database connections (`docs/decisions.md`, 2026-10-18). It replaces the first deployed
> run's R22 result; the R23, R24 and R38 results above are unchanged.

Measured 2026-10-18: the real-LLM run from 20:43:42 to 20:44:46 UTC, then the API-only run from
20:44:57 to 20:45:29 UTC.

**What changed since the first deployed run**

- Puma: one process with **24 threads** (`RAILS_MAX_THREADS=24`). Before, it had 3.
- Database pool: **6 connections** per process (`DB_POOL=6`), apart from the thread count. A chat
  request holds no connection while it waits on the LLM, so the 24 threads share 6 connections.
  Solid Queue's processes inside Puma use about 7 more, inside the session pooler's limit of
  about 15.
- Code: `35886c3`, which also includes the chat routing fix (`80ca414`). Same API URL, region
  (`sfo`), LLM (Claude Haiku 4.5, Groq fallback set) and client laptop as above. Fresh tokens for
  the same 20 load-test users, from `perf:users`.

**R22, k6 (20 VUs, 60 s, `LLM_MODE=real`), client-side**

| Endpoint | p95 | Median | Before (p95) |
| --- | --- | --- | --- |
| All requests | **1,949 ms** | | 8,025 ms |
| `GET /health` | 275 ms | 123 ms | 8,309 ms |
| `GET /slots` | 431 ms | 129 ms | 2,277 ms |
| `GET /onboarding` | 364 ms | 175 ms | 2,311 ms |
| `POST /chat/messages` | **2,432 ms** | 1,816 ms | 11,510 ms |
| `POST /bookings` | 588 ms | 253 ms | 8,808 ms |
| `DELETE /bookings/:id` | 283 ms | 225 ms | 4,410 ms |

Requests: 1,902 (505 before), error rate: 0.00%, HTTP 429 responses: 0, LLM rate-limited chat
replies: 0. Every k6 threshold passed, the per-endpoint p95 < 3 s included. The server's logs
for the window hold no 5xx and no connection-pool errors.

**Bookings and cancels.** The 409 count covers `POST /bookings` responses only, never cancels.
Of the 319 `POST /bookings` in the server's logs, 289 created a booking and 30 answered the
expected 409. `perf/load.js` treats two 409 codes as expected: `slot_taken`, when another virtual
user booked the random slot first, so nothing is cancelled; and `booking_exists`, when the user
still holds a booking from an earlier iteration, so the script looks it up with `GET /bookings`
and cancels that one. That gives the 307 `DELETE /bookings/:id`: one for each of the 289 new
bookings plus 18 after a `booking_exists`, which leaves 12 `slot_taken` with no cancel. The logs
don't split the 30 by code, so the 18/12 split is derived from those counts. The 1,902 is k6's
count of every request in the run, across all endpoints.

**Server-side for the same run** (Lograge, `railway logs --service api --json`, nearest-rank).
Chat lines now also carry `llm_calls` and `llm_ms`.

| Endpoint | Requests | p95 | Median |
| --- | --- | --- | --- |
| `POST /chat/messages` | 319 | 2,342 ms | 1,712 ms |
| of which LLM (`llm_ms`) | | 1,812 ms | 1,480 ms |
| of which database (`db`) | | 292 ms | 241 ms |
| `GET /slots` | 319 | 316 ms | 27 ms |
| `GET /onboarding` | 319 | 237 ms | 76 ms |
| `POST /bookings` | 319 | 493 ms | 153 ms |
| `DELETE /bookings/:id` | 307 | 184 ms | 127 ms |

All 319 chat requests made exactly one LLM call: no retry after an invalid answer and no fallback
provider. The chat time is the Haiku call plus about 240 ms of database work, which is about 11
queries at about 20 ms each from Railway `sfo` to Supabase us-west-2. The first run's 3.5 s
server-side chat p95 didn't recur. That run predated these log fields, so its cause can't be
pinned down; that run also had the earlier chat prompt. The non-chat endpoints' server p95 rose
from 32-168 ms to 184-493 ms: with 24 threads, more of them wait for one of the 6 connections
and share the GVL. That costs well under the 3 s budget.

**API only, k6 (20 VUs, 30 s, `LLM_MODE=off`), client-side:** all requests p95 **328 ms**;
`GET /health` 162 ms, `GET /slots` 160 ms, `GET /onboarding` 276 ms, `POST /bookings` 473 ms,
`DELETE /bookings/:id` 290 ms. 1,537 requests, error rate 0.00%, HTTP 429 responses 0.

**R22: met on the deployed app.** Overall p95 1.95 s and chat p95 2.43 s, both under 3.0 s,
with 0 errors. The margin for chat is about 0.6 s, and almost all of the chat time is the
provider's, so a slower provider hour could narrow it.

## Uptime (R25)

> **Not running yet.** This section states the check; the blanks below are filled in once the
> monitor is set up and the evaluation window has passed.

The check: an external uptime monitor sends `GET https://api-production-460eb.up.railway.app/health`
every 5 minutes. `/health` runs `SELECT 1` on the database, so a passing check means the API and
its database both answered. The same query also keeps the database active, so it doesn't pause
for inactivity during the window. R25 is met when the measured uptime over the window is at
least 99%.

| Item | Value |
| --- | --- |
| Monitor status page | _TBD: status-page URL_ |
| Evaluation window | _TBD: start and end, UTC_ |
| Measured uptime | _TBD: %_ |
