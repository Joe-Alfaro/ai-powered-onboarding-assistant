# Decisions log

Append-only. If a decision is reversed, add a new entry that names the one it replaces.

## 2026-10-15: Stack is a Rails API with a Next.js frontend

- **Decided by:** user
- **Decision:** Ruby on Rails API backend, Next.js (React, TypeScript) frontend, Supabase for
  Postgres and Auth, deployed on Railway.
- **Alternatives:** a single TypeScript stack (Next.js with API routes), or Render for hosting.
- **Tradeoffs:** Rails gives fast, conventional CRUD, migrations and RSpec for the scheduling and
  consent logic; Next.js gives a typed, accessible frontend. Two runtimes cost more setup and two
  deploy services. Supabase covers Auth and Postgres on a free tier.
- **Affects:** R19, R32, R35

## 2026-10-15: LLM provider is chosen by a multi-provider eval

- **Decided by:** user
- **Decision:** put the LLM behind a provider-swappable interface, run the same eval harness
  against Claude (Haiku and Sonnet), Groq, Gemini and Ollama, report every score, and pick the
  production provider from the results.
- **Alternatives:** pick one provider up front.
- **Tradeoffs:** costs an adapter per provider and eval runs, but gives a data-backed
  justification for the choice and a free provider for graders and for failover.
- **Affects:** R16, R21, R28

## 2026-10-15: One company-agnostic README and demo

- **Decided by:** user
- **Decision:** the README, docs and demo video present the app as a standalone product, with no
  audience-specific framing.
- **Alternatives:** separate READMEs or demos per audience.
- **Tradeoffs:** one set of docs to maintain; nothing audience-specific to tailor.
- **Affects:** Deliverables

## 2026-10-15: Requirements interpretations made while writing the requirements file

- **Decided by:** agent (pending user approval of the requirements file)
- **Decision:**
  - Intent list fixed to the five examples given: `provide-details`, `ask-question`,
    `request-reschedule`, `express-distress`, `out-of-scope`.
  - Supportive-content triggers fixed to the three examples given: long pause (configurable
    threshold), upload failure, high-stress intent (`express-distress`).
  - Assumed service domain: outpatient counseling intake, so HIPAA applies.
  - The minimal-data-to-LLM documentation rule, stated for one provider, applies to every provider.
  - Double-booking includes simultaneous requests, not just sequential ones.
  - Stretch goals are out of the done definition.
- **Alternatives:** a larger intent or trigger list; a financial-services domain (PCI DSS); a
  generic domain with no regime.
- **Tradeoffs:** the smallest lists that satisfy the examples keep the eval tractable.
  Counseling intake fits the emotional-stress framing and makes the privacy work concrete.
- **Affects:** R1, R7, R9, R20

## 2026-10-15: Gotcha hunt folded into the requirements

- **Decided by:** agent (pending user approval)
- **Decision:** a separate agent reviewed the PRD for easy-to-miss requirements. Confirmed items
  were added as **[gotcha]** requirements or done checks, indexed in the requirements file.
  Interpretations:
  - The `request-reschedule` intent can't be handled truthfully without a reschedule feature, so
    reschedule and cancel became R36 even though the scheduling feature only names view and book.
  - Timezone handling (R37) and deployed-environment performance (R38) were implied, not stated,
    and added as requirements.
  - "Field-level accuracy" gets a documented normalization rule (R4) rather than raw exact match.
  - "Bounded time" for failure messages is set to 10 s (R16, R30).
  - Abandoned, never-confirmed uploads are purged on a time-to-live (R17), since the retention
    rule otherwise only covers confirmed uploads.
  - The 15-minute completion target stays unmeasured, but the demo video shows a full run.
- **Not adopted:** redacting or tokenizing identity fields before every prompt was suggested as
  "ideal". R20 already requires the minimum, documented and contract-tested; the architecture
  decides whether redaction is needed.
- **Affects:** R2–R5, R7, R9, R11–R17, R19–R21, R23, R30–R38

## 2026-10-15: No service domain is assumed

- **Decided by:** user
- **Replaces:** the "assumed service domain: outpatient counseling intake" item in "Requirements
  interpretations made while writing the requirements file".
- **Decision:** the source material doesn't name the service, so the app stays domain-neutral. The
  compliance section says no domain is assumed and covers how the design would support HIPAA or
  PCI DSS if the app were used in those domains.
- **Alternatives:** assume counseling intake (HIPAA) or financial onboarding (PCI DSS).
- **Tradeoffs:** avoids inventing scope; costs a conditional compliance write-up instead of one
  concrete one.
- **Affects:** R20

## 2026-10-15: Host on Railway

- **Decided by:** user
- **Decision:** deploy on Railway, using the user's existing account.
- **Alternatives:** Render's free tier.
- **Tradeoffs:** Render's free instances sleep when idle, which breaks the cold-start check (R38)
  and the uptime target (R25). Railway costs a small monthly fee but doesn't sleep. Hosting cost
  isn't an API, so the "no paid API" rule (R21) is unaffected.
- **Affects:** R22–R25, R38

## 2026-10-15: Architecture choices

- **Decided by:** agent (pending user approval of ARCHITECTURE.md)
- **Decision:**
  - **All data through the Rails API:** the browser uses Supabase only to sign in. RLS is enabled
    with no policies for client roles.
  - **OCR runs in the request:** Tesseract runs synchronously in the API container, so OCR
    latency is measured from upload to response with no polling.
  - **Images kept until confirmation:** the image goes to a private bucket so the user can compare
    it with the extracted fields, then is deleted on confirm or after 1 hour if never confirmed.
  - **One LLM call per chat message:** returns intent, fields and reply. Booking facts in replies
    come from scheduler results, with a guard against unbacked dates or times.
  - **Two LLM adapters:** Anthropic, plus OpenAI-compatible for Groq, Gemini and Ollama. A 6 s
    timeout, and an optional fallback provider.
  - **Double-booking enforced by Postgres:** partial unique indexes on active bookings.
  - **Solid Queue inside Puma:** for the purge job, so no Redis and no separate worker service.
  - **Field-level encryption:** Active Record encryption on personal-data columns, on top of
    Supabase disk encryption.
  - **Local stack:** the Supabase CLI for local development and grading.
- **Alternatives:** the frontend reads Supabase directly with RLS policies; async OCR with polling;
  OCR without storing the image; a separate intent-classification call; a separate worker service
  with Redis; Railway Postgres instead of Supabase Postgres; a hosted Supabase project for graders.
- **Tradeoffs:**
  - Routing all data through the API puts every access check in one tested place.
  - Synchronous OCR is simpler and matches the PRD's timing method, at the cost of holding a Puma
    thread for a few seconds.
  - Storing the image briefly improves the confirmation UX but needs the purge job.
  - One LLM call keeps chat latency down.
  - The local Supabase stack makes grading self-contained but slower to start the first time.
- **Affects:** R3, R5, R7, R13, R16–R20, R23, R32, R36

## 2026-10-15: Uptime check runs on GitHub Actions

- **Decided by:** agent (pending user approval of ARCHITECTURE.md)
- **Decision:** the R25 uptime check is a scheduled GitHub Actions workflow that pings `/health`
  every 5 minutes, with a script that computes uptime from the run history.
- **Alternatives:** a third-party monitor (for example UptimeRobot); a Railway cron service that
  records checks in the database.
- **Tradeoffs:** the PRD asks only for "an uptime check, such as a cron ping". GitHub Actions needs
  no new account and checks from outside Railway, but scheduled runs can be delayed, so the report
  counts actual checks. A Railway cron would check from inside the same platform and cost more.
- **Affects:** R25, R38

## 2026-10-15: Requirements and architecture approved

- **Decided by:** user
- **Decision:** approved the requirements file (gotchas included) and ARCHITECTURE.md, including
  the agent entries above marked "pending user approval". Implementation can start.
- **Affects:** all

## 2026-10-15: Repository hosted on GitLab

- **Decided by:** user
- **Replaces:** "Uptime check runs on GitHub Actions", the GitHub Actions CI named in
  ARCHITECTURE.md, the "Public GitHub repository" deliverable, and the open question on the GitHub
  repository name and visibility.
- **Decision:** the repository lives on gitlab.com and is public now. Every change goes on a
  feature branch and reaches `main` through a Merge Request after CI passes. CI is GitLab CI
  (`.gitlab-ci.yml`). The R25 uptime check is a GitLab pipeline schedule that pings `/health`
  every 5 minutes, and the uptime report reads that schedule's pipeline history. Railway deploys
  through the Railway CLI, because Railway's native repository integration supports only GitHub.
- **Alternatives:** stay on GitHub with GitHub Actions; mirror GitLab to GitHub so Railway's
  native integration still works.
- **Tradeoffs:** GitLab CI covers the same gates and schedules. Deploying with the Railway CLI
  needs a Railway token stored as a GitLab CI variable instead of a click-through integration.
  Scheduled pipelines can also be delayed, so the uptime report still counts the checks that ran.
- **Affects:** R25, R35, Deliverables

## 2026-10-15: Workers may install system dependencies with Homebrew

- **Decided by:** user
- **Decision:** agents may `brew install` the system dependencies the architecture needs
  (Tesseract, libvips, libheif, the Supabase CLI, k6) when their task needs them.
- **Alternatives:** ask the user before each install; run everything only inside Docker.
- **Tradeoffs:** faster local work, at the cost of agents changing the user's machine. The README
  still has to list these dependencies for a clean checkout.
- **Affects:** R32

## 2026-10-15: Scaffold choices for the quality gates

- **Decided by:** agent
- **Decision:**
  - SimpleCov groups map the R29 modules to `app/services/ocr`, `app/services/chat` and
    `app/services/scheduling`, each with an 80% line minimum. A group with no files counts as
    100%, so the build passes until code lands, and every file under `app/` and `lib/` is
    reported even if no spec loads it, so an untested service counts as 0%.
  - Jest enforces an 80% global threshold on lines, branches, functions and statements.
  - Local Postgres for development and tests runs from `docker-compose.yml` on host port 5433
    (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`), so it doesn't collide with a Postgres
    already on 5432. CI uses a Postgres 17 service container.
  - The Rails app skips Action Mailer, Action Mailbox, Action Text, Active Storage, Action
    Cable, Kamal and Thruster, which the architecture doesn't use.
  - The pre-push hook runs RuboCop, ESLint, Prettier, `tsc` and Jest, and RSpec only when the
    database is reachable. CI always runs RSpec and the secret scan.
- **Alternatives:** an overall coverage minimum instead of per-group; mocking the database; a
  pre-push hook that requires Postgres.
- **Tradeoffs:** per-group minimums target R29 exactly but leave non-core code unenforced. Skipping
  RSpec locally without a database keeps pushes fast and possible, and CI still catches failures.
- **Affects:** R29, R32, R35

## 2026-10-15: Self-hosted GitLab with a GitHub mirror

- **Decided by:** user and orchestrator
- **Replaces:** the gitlab.com hosting and the Railway CLI deploy from GitLab CI in "Repository
  hosted on GitLab".
- **Decision:** the repository is hosted on a self-hosted GitLab server (the `gitlab` remote), with
  GitHub kept as a mirror (`origin`). Merge requests go to GitLab; no pull requests on GitHub.
  `main` is protected and changes only through merge requests with a passing pipeline. Agents
  follow the GitLab server safety rules in `CLAUDE.md`.
- **Alternatives:** gitlab.com; GitHub only.
- **Tradeoffs:** matches the setup of the user's other project on the same server. The server is
  shared and has been taken down by runaway loops, so CI must stay small and polling is limited.
  With no `main` pipelines, Railway can't be deployed from GitLab CI, so the deploy mechanism is
  open again (see ARCHITECTURE.md).
- **Affects:** R25, R35, Deliverables

## 2026-10-15: R35 CI runs on merge-request pipelines (requirement change)

- **Decided by:** user and orchestrator
- **Replaces:** the "on every push to any branch" wording in R35, and "runs on every push to any
  branch" in "Repository hosted on GitLab", and the CI Postgres service container and the
  pre-push subset in "Scaffold choices for the quality gates".
- **Decision:** R35's done check becomes "on every push to a branch with an open merge request
  (merge-request pipelines)". The pipeline is a single `gates` job on a shell-executor runner that
  runs `bin/gates`, the same script as the pre-push hook, including the secret scan. The job starts
  its own Postgres container on port 55433 and removes it when it ends. Locally, `bin/gates` skips
  RSpec when no Postgres is reachable and the secret scan when gitleaks isn't installed; in CI both
  are required.
- **Alternatives:** branch pipelines on every push; separate jobs per gate; a Postgres `services:`
  container.
- **Tradeoffs:** required by the server safety rules. Branches without an MR get no CI, but the
  pre-push hook runs the same gates locally, and nothing reaches `main` without an MR pipeline.
  One job gives less parallelism and less granular status than one job per gate.
- **Affects:** R33, R35

## 2026-10-15: Uptime check mechanism is open again

- **Decided by:** user and orchestrator
- **Replaces:** "Uptime check runs on GitHub Actions" and the GitLab pipeline schedule in
  "Repository hosted on GitLab".
- **Decision:** the R25 uptime check can't be a GitLab scheduled pipeline, because schedules are
  forbidden on the GitLab server. The mechanism is an open question and isn't built yet.
- **Alternatives:** a GitHub Actions cron on the GitHub mirror; an external free uptime monitor.
- **Tradeoffs:** deferred until deployment work starts.
- **Affects:** R25

## 2026-10-15: GitLab is the only remote

- **Decided by:** user
- **Replaces:** "Self-hosted GitLab with a GitHub mirror".
- **Decision:** the self-hosted GitLab is the repository's only remote, named `origin`. There is no
  GitHub project or mirror. Merge requests, CI and the public repository deliverable are all on
  GitLab. The R25 uptime check uses an external free uptime monitor (still to be chosen), and
  Railway deploys use the Railway CLI.
- **Alternatives:** keep a GitHub mirror, which would allow a GitHub Actions cron for uptime and
  Railway's native GitHub integration for deploys.
- **Tradeoffs:** one remote to keep in sync and nothing on GitHub to maintain. Deploys need the
  Railway CLI instead of a push-to-deploy integration, and the uptime check needs an outside
  service.
- **Affects:** R25, Deliverables

## 2026-10-15: Trigger engine contract set by the R9 tests

- **Decided by:** agent (test agent, web-trigger-engine)
- **Decision:** the R9 tests fix this contract for the implementer. `web/src/support/triggers.ts`
  exports `TriggerId`, the `TRIGGERS` table (`{ content: { heading, message } }` per trigger),
  `DEFAULT_LONG_PAUSE_SECONDS` (45) and `longPauseThresholdMs()`, which reads
  `NEXT_PUBLIC_LONG_PAUSE_SECONDS` and falls back to 45 s for an empty, non-numeric or non-positive
  value. `web/src/support/triggerEngine.ts` exports `createTriggerEngine({ longPauseMs? })` with
  `start`, `stop`, `reportUpload({ ok, status? })`, `reportChatResponse({ reply, trigger? })`,
  `active()` and `subscribe()`. `<SupportiveContent engine={engine} />` renders each active
  trigger's table content as a heading and message inside a `status` live region. A chat response
  activates content only when `trigger` is exactly `"high-stress-intent"`; any other flag value
  (including other trigger IDs) and all reply text are ignored. An upload with `ok: false`,
  whether rejected (4xx/5xx) or failed (no response), fires `upload-failure`. When the tab comes
  back from hidden, the tests allow the long-pause timer to either resume or restart, but it must
  not fire on the instant of return.
- **Alternatives:** a hook returning active triggers; a presentational component taking trigger
  IDs; letting the chat flag name any trigger.
- **Tradeoffs:** passing the engine to the component keeps reply text out of the rendering path
  by construction. Accepting only one chat flag value means the API can't widen what the LLM can
  trigger without a web change, which is the point of the R9 gotcha.
- **Affects:** R9, R34

## 2026-10-15: Trigger engine runtime behavior

- **Decided by:** agent (implementation agent, web-trigger-engine)
- **Decision:** the long-pause timer restarts from zero on `keydown`, `input`, `focusin` and
  `pointerdown` (captured on `document`) and on every `visibilitychange`; it is cleared while the
  tab is hidden. Returning to the tab restarts the full threshold rather than resuming it. A fired
  trigger stays active until the engine is recreated (no dismissal yet), and fires only once.
  `SupportiveContent` always renders its empty `status` region so screen readers announce content
  added later.
- **Alternatives:** resuming the remaining time on return to the tab; clearing `long-pause` on the
  next activity.
- **Tradeoffs:** restarting on return is simpler and the happy-path test needs it (resuming would
  fire after a short tab switch late in a step). Sticky content avoids flicker and repeated
  announcements, but a dismiss control may be wanted once the steps are built.
- **Affects:** R9, R34

## 2026-10-15: LLM client interface fixed by the llm-client specs

- **Decided by:** agent (test agent, llm-client)
- **Decision:**
  - `Llm::Client.from_env(env)` builds the client from `LLM_PROVIDER`, `LLM_MODEL`,
    `LLM_FALLBACK_PROVIDER` and a new optional `LLM_FALLBACK_MODEL`; an unset model uses a
    per-provider default. `Llm::Client.new(primary:, fallback:)` takes adapters directly, which is
    the seam the chat slice uses with `FakeLlmAdapter` (`spec/support/fake_llm_adapter.rb`).
  - Adapters expose `#complete(payload, timeout:)` and return `Llm::Response` (`data`, `provider`,
    `model`). `Llm::Adapters::Anthropic.new(api_key:, model:, base_url:)` and
    `Llm::Adapters::OpenAiCompatible.new(provider:, base_url:, api_key:, model:)`, where `base_url`
    is the API root (`.../openai/v1`, `.../v1beta/openai`, `OLLAMA_BASE_URL + "/v1"`).
  - Provider names are `anthropic`, `groq`, `gemini`, `ollama`, keyed by `CLAUDE_API_KEY`,
    `GROQ_API_KEY`, `GEMINI_API_KEY`; Ollama needs no key. A missing or blank key, or an unknown
    or unset provider, raises `Llm::ConfigError` naming the variable. `Llm::Providers.configured`
    lists providers with credentials, so the eval harness can skip the rest.
  - Typed errors subclass `Llm::Error`, each with a `code` (`llm_timeout`, `llm_server_error`,
    `llm_rate_limited`, `llm_unreachable`) and `actions` = `try_again`, `continue_manually`, for the
    error envelope. Malformed output is `Llm::InvalidResponseError`.
  - The fallback is tried once on a timeout, 5xx or 429 only, not on other 4xx, connection
    failures are not required to fall back, and malformed output never falls back (the chat layer
    owns its one validation retry). The primary and fallback together must fail within 10 s, so
    the fallback cannot simply get a second full 6 s.
  - `Llm::PayloadBuilder.new(identity:).build(system:, turns:, assessment_draft:, response_schema:)`
    returns an `Llm::Payload` that other code can't construct. Identity values become `[NAME]`
    (full name and each name part as whole words), `[DATE_OF_BIRTH]` (ISO, US numeric, and written
    month formats) and `[ADDRESS]` (full address and street line), case-insensitively, in every
    turn and the draft. Draft keys the response schema doesn't declare under `assessment_fields`
    are dropped. Non-text, binary, invalid UTF-8 or `data:image/` content raises
    `Llm::PayloadBuilder::DisallowedContent`.
  - `docs/data-to-llm.md` lists the fields sent in a `## Fields sent` table, one backticked field
    ID per row. The contract spec seeds distinctive values and compares what it finds in the real
    request body to that list; with the design above the list is `message_text` and
    `assessment_draft`.
- **Alternatives:** a fixed 6 s per attempt (12 s worst case, over R16's 10 s); no fallback model
  variable (the primary's model name would be wrong for another provider); one contract field
  per assessment key (the assessment schema belongs to the chat slice).
- **Tradeoffs:** two R16 specs wait on the real clock (about 6 s and 9 s) so the 10 s bound is
  measured, not assumed. Name-part redaction can over-redact a word that happens to equal a name.
- **Affects:** R16, R20, R21

## 2026-10-15: LLM client runtime behavior and default models

- **Decided by:** agent (implementation agent, llm-client)
- **Decision:**
  - The client has a 9 s budget for the primary and the fallback together. The primary gets 6 s;
    the fallback gets the lesser of 6 s and what is left, and is skipped if under 1 s is left.
  - Connection failures (refused, reset, DNS, TLS) also go to the fallback, alongside timeouts,
    5xx and 429. A 4xx other than 429 (`Llm::RequestError`, code `llm_request_rejected`) and
    malformed output do not.
  - Adapters use `Net::HTTP` with no new gem: open, read and write timeouts set to the call's
    timeout, `max_retries = 0` and debug output off. Error messages name the provider and status,
    never a key or the payload.
  - Default models when `LLM_MODEL` is unset: `claude-haiku-4-5` (Anthropic), `openai/gpt-oss-20b`
    (Groq), `gemini-2.5-flash` (Gemini), `llama3.2` (Ollama). There is no Claude Haiku 5.5 model;
    the current Haiku is Claude Haiku 4.5. Claude Sonnet 5.5 is `claude-sonnet-5-5`.
  - Claude Sonnet 5.5 (and Opus 5.5, Fable 5.1, Mythos 5.1) reject a forced `tool_choice`. For
    those models the Anthropic adapter sends `tool_choice: auto`, adds "always answer by calling
    the respond tool" to the system prompt and sets low effort for latency. A reply without the
    tool call is `Llm::InvalidResponseError`, which the chat layer's one retry covers. Other models
    (Haiku 4.5 included) get the forced tool choice.
  - The payload builder puts the filtered assessment draft into the system prompt as JSON. It
    redacts message turns and draft values but not the system prompt, which we write. Name parts
    shorter than two characters (initials) aren't redacted on their own.
  - `Llm::ConfigError` is not an `Llm::Error`: it is a deploy problem with no user actions.
  - `api/.env.example` documents `LLM_FALLBACK_MODEL` and names the Anthropic provider
    `anthropic`, not `claude`.
- **Alternatives:** Faraday or the Anthropic Ruby SDK (a new dependency, with retries and timeouts
  to turn off, for two small POSTs that need identical error mapping across providers); a hard
  `Timeout.timeout` around each request; forcing tool use on every model.
- **Tradeoffs:** per-operation timeouts don't bound a server that sends bytes slowly forever, but
  avoid `Timeout.timeout`'s thread-safety problems. Default models are guesses until the R28 eval
  picks them; `LLM_MODEL` overrides them with no code change. Auto tool choice on the 5.5 models
  can produce more invalid responses than forced tool use; the eval will show how many.
- **Affects:** R16, R20, R21, R28

## 2026-10-15: API foundation contracts set by the tests

- **Decided by:** agent (test agent, api-foundation)
- **Decision:** the api-foundation specs fix these interfaces for the implementation and for the
  slices built in parallel:
  - **Auth:** `Auth::JwtVerifier.new(jwks_url:, issuer:)` with `#verify(token)` returning an
    identity with `user_id` (the `sub` claim) and `admin?`. It accepts ES256 and RS256 keys from
    the JWKS, requires `exp`, `sub`, issuer `<SUPABASE_URL>/auth/v1` and audience `authenticated`,
    and caches the JWKS in memory. Failures raise `Auth::JwtVerifier::InvalidToken` (401) or
    `Auth::JwtVerifier::JwksUnavailable` (503 `auth_unavailable`).
  - **Admin role:** only `app_metadata.role == "admin"` counts. `user_metadata` and the top-level
    `role` claim are ignored, because users can edit `user_metadata` themselves.
  - **Controllers:** every `ApplicationController` subclass requires a bearer token by default and
    exposes `current_user_id`; admin endpoints use `before_action :require_admin!`, which writes
    one `AuditEvent` per admin access. Public endpoints such as `/health` opt out explicitly.
  - **Audit actor_ref:** hex HMAC-SHA256 of the user ID keyed by `AUDIT_HMAC_KEY`.
  - **Error codes:** `unauthorized` 401, `forbidden` 403, `not_found` 404 (including unknown
    routes), `invalid_request` 400 (missing params), `validation_failed` 422,
    `database_unavailable` 503 (any `ActiveRecord::ConnectionNotEstablished`), `internal_error`
    500 with a generic message. Other slices raise `ApiError.new(status:, code:, message:,
    actions:)` to get their own envelope, for example `llm_unavailable` with
    `actions: ["retry", "manual"]`.
  - **Health:** `Health::Check.new(probes:).call` returns
    `{ status: "ok" | "degraded" | "down", checks: { app:, database:, storage:, ocr:, llm: } }`,
    each check `{ status: "ok" | "down" }`. A probe is any callable; `false` or an exception
    means down. `/health` returns 503 only when the database is down. `Health::Check.probes` is
    the app's registry: the database probe runs on every ping; storage, OCR and LLM are wrapped
    in `Health::CachedProbe.new(probe, ttl:)` with a ttl of at most 5 minutes. The OCR, LLM and
    storage slices register their real probes there.
  - **Logs:** every log line, including errors, goes through `Rails.logger` as one JSON object.
    Error entries name the exception class but never include its message.
  - **RLS:** enabled on every table in the `public` schema, Rails' own `schema_migrations` and
    `ar_internal_metadata` included, with no policy for `anon`, `authenticated` or `public`.
- **Alternatives:** admin role in a custom claim or a database table; plain SHA-256 for
  `actor_ref`; flat health statuses; exempting Rails' internal tables from RLS.
- **Tradeoffs:** a keyed HMAC can't be reversed by hashing guessed user IDs. Nested health checks
  leave room for latency or detail fields later. RLS on the internal tables keeps a leaked anon
  key from even reading the migration history, and keeps the spec a single catalog query that
  covers future tables. Because `schema.rb` doesn't record RLS, the implementation needs a way to
  get it into the test database (for example a SQL schema format).
- **Affects:** R15, R19, R30, R31
