# Performance (R22, R23, R24, R38)

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
then `POST /bookings` on a random open slot and `DELETE /bookings/:id` to cancel it, then sleeps
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

> **To fill in at deploy time.** Run all three against the deployed API URL with the production
> provider (`LLM_MODE=real`), after `bin/rake perf:users` against the production Supabase project.
> R38 also asks for the first request after 30 minutes idle; record it here too.

Measured: _date and time (UTC)_

**Setup:** _API URL (no secrets), service plan and region, Puma threads, LLM provider and model,
whether the fallback provider is set_

**R22, k6 (20 VUs, 60 s, `LLM_MODE=real`)**

| Endpoint | p95 | Median |
| --- | --- | --- |
| All requests | _ | |
| `GET /health` | _ | _ |
| `GET /slots` | _ | _ |
| `GET /onboarding` | _ | _ |
| `POST /chat/messages` | _ | _ |
| `POST /bookings` | _ | _ |
| `DELETE /bookings/:id` | _ | _ |

Requests: _, error rate: _, HTTP 429 responses: _, LLM rate-limited chat replies: _

**R23, OCR (20 uploads):** server-side p95 _, client-side p95 _ (from _where the client ran_)

**R24, booking (20 bookings):** server-side p95 _

**R38, first request after 30 minutes idle:** _

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
for the window hold no 5xx and no connection-pool errors; 30 `POST /bookings` answered the
expected 409.

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
