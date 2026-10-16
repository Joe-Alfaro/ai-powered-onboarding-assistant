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

## 2026-10-15: API foundation implementation choices

- **Decided by:** agent (implementation agent, api-foundation)
- **Decision:**
  - **RLS without a SQL schema:** `schema.rb` stays the schema format. `lib/boot/row_level_security.rb`
    is prepended to `ActiveRecord::Migrator` and `ActiveRecord::Schema::Definition`, and after every
    migration run and every schema load it enables RLS on each `public` table that lacks it. New
    tables from other slices get RLS with no extra migration code.
  - **JWT:** the `jwt` gem, ES256 and RS256 only. The JWKS is cached for 10 minutes. A token with an
    unknown `kid` forces a refetch at most once a minute. If a refresh fails while keys are cached,
    the cached keys stay in use, and `JwksUnavailable` is raised only when no keys were ever fetched.
  - **Logs:** `JsonLogFormatter` is the `Rails.logger` formatter in every environment. It merges
    Lograge's JSON line into one entry and wraps any other message as `message`. Production drops
    `log_tags`, because a tag prefix breaks the JSON, and logs `request_id` as a Lograge field
    instead. A rescued error adds `error_class`, `error_code` and, for 500s, five cleaned backtrace
    lines to the request's single line.
  - **Unknown routes:** a catch-all `match "*path"` route, kept last in `routes.rb`, raises
    `RoutingError` into the same `rescue_from` layer. No custom `exceptions_app`.
  - **Health placeholders:** storage, OCR and LLM are registered in `Health::Check.probes` as
    `CachedProbe(Probes::NotConfigured)` and report `down` until each slice swaps in its real probe
    on that line. The registry is memoized so the cache survives across pings.
- **Alternatives:** `schema_format = :sql`, which needs `pg_dump` and `psql` on the shared runner
  host, and neither is installed; enabling RLS per migration by hand; a Postgres event trigger,
  which `schema.rb` can't record either; reporting unbuilt probes as `ok`.
- **Tradeoffs:** the hook is implicit, but the RLS spec queries the catalog, so a regression is
  caught. Serving a stale JWKS keeps users signed in during a JWKS outage, at the cost of trusting
  a revoked key for up to one more refresh cycle. A `down` placeholder shows `/health` as degraded
  until the OCR, LLM and storage slices land, which is honest about what isn't built.
- **Affects:** R15, R19, R30, R31

## 2026-10-15: Error envelope action vocabulary

- **Decided by:** agent (implementation agent, api-foundation), at the orchestrator's direction
- **Decision:** `actions` in the error envelope uses only `retry` and `manual_entry`, the values
  the web shell's tests expect. This replaces the `["retry", "manual"]` example in "API foundation
  contracts set by the tests". The foundation's 401 `unauthorized` envelope now has no actions
  (it was `["sign_in"]`). The web app handles a 401 by its code.
- **Alternatives:** a wider action list, with a `sign_in` action for 401s.
- **Tradeoffs:** one small vocabulary keeps the web shell's action handling exhaustive. Slices
  that emit their own actions (for example `Llm::Error`) need to match it.
- **Affects:** R16, R30

## 2026-10-15: Scheduling contracts set by the tests

- **Decided by:** agent (test agent, scheduling)
- **Decision:** the scheduling specs fix these interfaces for the implementation and for the chat
  slice's `request-reschedule` handler:
  - **Tables:** `slots` (`starts_at`, `ends_at` as timestamptz) and `bookings` (`slot_id`,
    `user_id`, `status` of `"active"` or `"cancelled"`), with partial unique indexes on
    `slot_id` and on `user_id` where `status = 'active'`. A user holds at most one active
    booking; cancelled rows stay as history.
  - **Service:** `Scheduling::Booker.new(user_id:)` with `#book(slot_id:)`,
    `#reschedule(booking_id:, slot_id:)` and `#cancel(booking_id:)`. Each returns a result, never
    raises for a conflict, with `success?`, `outcome`, `booking`, `slot` (the slot now held or
    requested), `previous_slot` (the slot freed) and `to_h`, which gives plain data with
    ISO-8601 UTC strings for reply templates. Outcomes: `:booked`, `:rescheduled`, `:cancelled`,
    `:slot_taken`, `:booking_exists`, `:not_found`. Another user's booking, or one already
    cancelled, is `:not_found`. A unique-index violation maps to `:slot_taken`.
  - **Endpoints:** `GET /slots` (open, future, soonest first), `GET /bookings` (the caller's
    active bookings), `POST /bookings`, `GET|PATCH|DELETE /bookings/:id` (`PATCH` reschedules,
    `DELETE` cancels and returns the booking with status `cancelled`), and admin-only
    `POST /admin/slots` and `DELETE /admin/slots/:id`. Bookings render as
    `{ id, status, slot: { id, starts_at, ends_at } }`.
  - **Errors:** `slot_taken` 409 with a message saying the slot is already booked;
    `booking_exists` 409; `not_found` 404 for unknown slots and other users' bookings.
  - **Times:** every time the API returns is ISO-8601 UTC with a `Z` suffix, whatever the server
    time zone is. The web converts to local time with a zone label.
  - **R24 timing:** the request log line from the foundation (method, path, status, duration)
    is the booking timing record, including for rejected bookings. No separate timing event.
- **Alternatives:** raising exceptions from `Booker` for conflicts; reschedule as cancel plus a
  new booking; a dedicated timing log event; slot management under `/slots`.
- **Tradeoffs:** a result object lets the chat handler template every outcome, failures
  included, from real data (R3). The specs accept reschedule either in place or as a new row,
  since they check only the response and which slots hold active bookings. The parallel specs
  run without transactional fixtures and widen the connection pool to 25 for their duration.
- **Affects:** R6, R7, R8, R19, R24, R36, R37

## 2026-10-15: Scheduling implementation choices

- **Decided by:** agent (implementation agent, scheduling)
- **Decision:**
  - **UUID keys:** `slots` and `bookings` use `gen_random_uuid()` primary keys, and
    `bookings.user_id` is a `uuid` (the token's `sub`). An unknown or malformed ID casts to no
    match and reads as `not_found`, never as a 500 or a partial integer match.
  - **Reschedule in place:** `Booker#reschedule` locks the caller's active booking row and
    updates its `slot_id`, so the booking ID survives the move. A unique violation rolls back the
    savepoint and returns `slot_taken`.
  - **Conflict mapping:** `Booker#book` checks for an existing booking first for a clear outcome,
    then relies on the partial unique indexes. A `RecordNotUnique` is mapped by the violated
    constraint's name: the slot index gives `slot_taken`, the user index gives `booking_exists`.
    Each change runs with `requires_new: true`, so a violation never aborts a caller's
    transaction.
  - **Admin slot removal:** `DELETE /admin/slots/:id` locks the slot row and refuses with 409
    `slot_booked` while it has an active booking; otherwise it deletes the slot and its cancelled
    bookings. The row lock conflicts with the key-share lock a new booking's foreign key takes, so
    a booking can't land between the check and the delete.
  - **Error actions:** `slot_taken`, `booking_exists`, `not_found` and `slot_booked` carry an
    empty `actions` list, since the envelope vocabulary is only `retry` and `manual_entry` and
    neither applies. The web app branches on the code.
  - **R24:** no extra log event. The foundation's Lograge line for each bookings request carries
    method, path, status and duration.
- **Alternatives:** bigint keys; reschedule as cancel plus a new row; a 409 retry loop; cascading
  slot deletes to active bookings.
- **Tradeoffs:** removing a slot drops its cancelled-booking history, which is acceptable for
  admin-managed availability and keeps the foreign key strict.
- **Affects:** R6, R7, R8, R19, R24, R36, R37

## 2026-10-15: Chat contracts set by the tests

- **Decided by:** agent (test agent, chat)
- **Decision:** the chat specs fix these interfaces for the implementation and for the slices
  built in parallel:
  - **Orchestrator:** `Chat::Orchestrator.new(user_id:, llm_client:).handle(message:, booking_id: nil,
    slot_id: nil)` returns a result with `reply`, `intent`, `trigger`, `actions`, `assessment` and
    `scheduling`. Each message gets a new orchestrator (as each request does), so the assessment
    draft lives in the database between messages. Each intent goes to its handler,
    `Chat::Handlers::ProvideDetails`, `AskQuestion`, `RequestReschedule`, `ExpressDistress` or
    `OutOfScope`, instantiated once per message. The LLM's `response_schema` lists the five
    intents and exactly the assessment schema's properties under `assessment_fields`.
  - **Assessment schema:** `api/app/schemas/assessment.json`, a valid JSON Schema (validated with
    the `json_schemer` gem) requiring `reason` and `preferred_window` (non-empty strings),
    `urgency` (`low`, `medium` or `high`), `distress` (boolean) and `notes` (string, may be
    empty), with no other properties. The record is complete, saved to `assessments` (with a
    `schema_version`) and returned as `assessment` once reason, urgency and preferred window are
    known; `distress` defaults to false and `notes` to an empty string. The express-distress
    handler sets `distress` true itself. Every `assessments` row validates against the schema, so
    an incomplete draft must live elsewhere. `assessment` is nil on every other message.
  - **Validation:** LLM output with an intent outside the list, a missing or non-string `reply`,
    missing or non-object `assessment_fields`, or a field value the schema rejects, and an
    `Llm::InvalidResponseError`, are retried once. A second failure gives the out-of-scope reply
    with a `continue_manually` action. Nothing from an invalid answer reaches the draft or the
    database. Timeouts, 5xx, 429 and connection failures are not retried by the chat layer.
  - **Fallbacks:** the out-of-scope reply is fixed text pointing back to onboarding, whatever the
    LLM wrote. Empty or whitespace-only messages get a reply without an LLM call. Messages are
    capped below 10,000 characters before they reach the LLM.
  - **Reply guard:** a reply stating a day, date, clock time or booking claim that no handler
    result backs is replaced by the handler's template. `request-reschedule` calls
    `Scheduling::Booker.new(user_id:).reschedule(booking_id:, slot_id:)` only when the request
    names both; its reply comes from the result's `success?`, `outcome` and `to_h`, and `to_h` is
    returned as `scheduling`. The reply text states the outcome; the web shows the time from
    `scheduling` in the user's local zone (R37), since the API doesn't know it.
  - **Trigger:** `trigger` is `"high-stress-intent"` for express-distress and nil otherwise, even if
    the LLM output carries a `trigger` key.
  - **Consent seam:** `Consent::Ledger.withdrawn?(user_id)` is asked before every LLM call,
    including the validation retry. True raises `Chat::ConsentWithdrawn`, which the API maps to
    403 `consent_withdrawn`, with no LLM call and nothing saved. Confirmed by the orchestrator:
    R12's consent gates the document upload, not chat.
  - **Endpoint:** `POST /chat/messages` with `{ message, booking_id?, slot_id? }` returns
    `{ reply, intent, trigger, actions, assessment, scheduling }`. A missing message is treated as
    empty (200 with a reply, not 400). LLM failures return 503 with the `Llm::Error`'s `code`,
    a message and `actions: ["retry", "manual_entry"]`. The fallback reply after two malformed
    answers carries `manual_entry` in its `actions` too. `retry` and `manual_entry` are the
    envelope's wire vocabulary, which the web reads (its ErrorNotice tests use them); the
    service-level result keeps `Llm::Error`'s internal names (`try_again`, `continue_manually`)
    and the chat API maps them at the HTTP boundary.
  - **Eval sets:** `api/eval/chat/intents.yml` (at least 5 labeled utterances per intent),
    `conversations.yml` (scripted turns with the fake LLM's output and the expected record) and
    `adversarial.yml`. The specs and the eval harness (R27) share them.
- **Alternatives:** gating chat on `Consent::Ledger.active?` as ARCHITECTURE says; requiring the
  LLM to supply `distress` and `notes`; putting the slot time in the reschedule reply text;
  sending `Llm::Error`'s `try_again` and `continue_manually` on the wire.
- **Tradeoffs:** the onboarding flow has chat before consent, so `active?` would block every new
  user's first message; `withdrawn?` still stops all LLM calls after revocation (R13), and the
  consent slice must provide it. Defaults for `distress` and `notes` let real providers that omit
  them still complete an assessment. Keeping times out of reply text keeps the guard simple and
  local-time display in one place. Three action vocabularies existed (web: `retry` and
  `manual_entry`; foundation: `retry`; `Llm::Error::ACTIONS`: `try_again` and
  `continue_manually`); the orchestrator chose the web's as the wire contract, so the mapping
  lives in one place at the API boundary.
- **Affects:** R1, R2, R3, R9, R13, R16, R36

## 2026-10-15: Chat implementation choices

- **Decided by:** agent (implementation agent, chat)
- **Decision:**
  - **Draft storage:** the incomplete assessment lives in `conversations.assessment_draft`
    (encrypted JSON), one conversation per user. `assessments` holds one row per user, upserted
    when the draft completes or a later message changes a field. `assessment` is returned only on
    the message that saved it.
  - **Encryption:** `conversations.assessment_draft`, `messages.content` and `assessments.data` use
    Active Record encryption. Keys come from the `ACTIVE_RECORD_ENCRYPTION_*` variables; the test
    environment sets fixed test-only keys. `messages.intent` stays plain, since it is one of five
    labels and holds no personal data.
  - **Validation:** our own checks, not the provider's structured output, are the gate. Fields the
    schema doesn't define are dropped; `null` and `""` count as not provided, because providers with
    strict schemas tend to send every property. `minLength` is left out of the schema sent to the
    LLM, since not every provider accepts it. The retry's system prompt names what was wrong
    (intent, reply or a field path), never the rejected values.
  - **Input:** messages are cut to 4,000 characters and stripped of control characters before they
    are stored or sent. Content `Llm::PayloadBuilder` still refuses (an inline image) gets the
    out-of-scope fallback with no LLM call.
  - **Replies:** `request-reschedule` and `out-of-scope` never use the LLM's text. The reply guard
    swaps any other LLM reply that mentions a day name, today, tomorrow, a clock time, a calendar
    date or a booking claim for the handler's template. It errs towards swapping, so a harmless
    "how are you feeling today?" also becomes the template.
  - **Persistence:** each answered message saves the user and assistant turns as a pair, the
    fallback included, and the last 10 are sent with the next call. Nothing is saved on a consent
    withdrawal, an empty message or an LLM failure.
  - **503 message:** the LLM failure envelope uses one fixed user-facing message, not the
    `Llm::Error`'s own text, with the error's `code` and the mapped actions.
  - **Seams:** `Consent::Ledger.withdrawn?` returns false until the consent slice fills it in.
    `Scheduling::Booker` comes from the scheduling slice. `Llm::PayloadBuilder` gets an empty
    identity until an onboarding record with the user's confirmed name, date of birth and
    address exists, so chat redaction of those values starts when that slice wires it in.
- **Alternatives:** a `status` column on `assessments` for drafts (breaks "every row validates");
  one assessment row per completion; rejecting extra fields with a retry; a narrower reply guard.
- **Tradeoffs:** upserting keeps one current assessment per user, matching "saved to the user's
  onboarding record". A conservative guard costs an occasional generic reply but never lets an
  unbacked time through (R3). Until the onboarding slice lands, chat sends identity values the
  user types into a message as typed.
- **Affects:** R1, R2, R3, R9, R13, R16, R18, R20

## 2026-10-15: Web shell contract set by the shell tests

- **Decided by:** agent (test agent, web-shell)
- **Decision:** the web-shell tests fix this contract for the implementer and for the page slices.
  - `web/src/api/client.ts` exports `createApiClient({ baseUrl, getAccessToken, timeoutMs? })`
    with `request<T>(path, { method?, body? })`, `ApiError` (built from
    `{ status, code, message, actions }`) and `DEFAULT_TIMEOUT_MS`, which must be over 6 s (so the
    API's own 503 after its 6 s LLM timeout can arrive) and under 10 s (R30). The client asks for
    a fresh token on every request, sends it as `Authorization: Bearer`, and sends no user ID.
    With no token it rejects with code `unauthenticated` without calling fetch. Plain-object
    bodies go as JSON; `FormData` goes untouched. Client-made codes are `network_error` and
    `timeout` (status `null`) and `unavailable` (a 5xx with no envelope), each with `['retry']`
    and a friendly message instead of the raw one.
  - **Envelope actions are snake_case strings:** `retry` and `manual_entry`. The client drops
    any other action. The API's `rescue_from` layer must use these exact values.
  - `web/src/api/ErrorNotice.tsx` renders the message in an `alert` with "Try again" and "Enter
    details manually" buttons for the listed actions.
  - `web/src/auth/supabase.ts` exports `getSupabaseClient()` (one memoized client, reading the
    `NEXT_PUBLIC_SUPABASE_*` variables when first created, not at import) and `getAccessToken()`
    (`null` when signed out or on error). `web/src/auth/SignInForm.tsx` signs in with email and
    password and calls `onSignedIn`. Neither reads tables or storage.
  - `web/src/time/formatLocalDateTime.ts` exports `formatLocalDateTime(iso, { locale?,
    timeZone? })`, which defaults to the browser's zone, shows the date, the time and a short
    zone label, and throws `RangeError` on a string without `Z` or an offset.
  - `web/src/shell/steps.ts` (`STEPS`, `stepFromPath`) and `web/src/shell/AppShell.tsx`
    (`<AppShell currentStep>`): a skip link first, a banner, an `Onboarding steps` nav with an
    ordered list, `aria-current="step"` plus visible "current" text, earlier steps as links
    marked "completed", later steps not linked, and one `main`. The `(onboarding)` route group
    layout derives the step from `usePathname()`.
  - `web/src/app/error.tsx` uses the Next 16 `retry` prop and never shows the error message;
    `web/src/app/not-found.tsx` links back to `/`.
  - Jest runs with `TZ=America/New_York` (set in `jest.config.mjs`), because Jest gives each test
    file a copy of `process.env` and a test can't change the zone itself.
- **Alternatives:** returning a result union instead of throwing `ApiError`; kebab-case action
  names to match intent IDs; changing the zone per test; letting users jump to any step.
- **Tradeoffs:** throwing keeps the success path of every page simple. Snake_case matches what a
  Rails JSON response naturally emits. A fixed suite-wide zone makes the default-zone test real
  but tests other zones only through the `timeZone` option. Keeping later steps unlinked stops
  users skipping consent or confirmation from the nav.
- **Affects:** R16, R19, R30, R34, R37

## 2026-10-15: Web shell implementation choices

- **Decided by:** agent (implementation agent, web-shell)
- **Decision:**
  - `DEFAULT_TIMEOUT_MS` is 8 s: 2 s of headroom over the API's 6 s LLM timeout for its 503
    envelope to arrive, and 2 s under the 10 s budget for the retry to show (R30).
  - A 4xx with no envelope becomes code `request_failed` with no actions; a missing token becomes
    `unauthenticated` with status 401 and no actions, so the page sends the user to sign in rather
    than retrying.
  - `ErrorNotice` shows an action's button only when the page passes the matching handler, so a
    page can't show a button that does nothing.
  - `formatLocalDateTime` shows weekday, date, year, time and the short zone name, using
    `Intl.DateTimeFormat` with no date library.
  - `SignInForm` is built and tested but not yet placed on a page: the home page test renders it
    outside the App Router, where `useRouter` throws. The page slice that owns sign-in mounts it
    and routes to `/chat` in `onSignedIn`.
- **Alternatives:** a timeout of exactly 6 s or 9.5 s; always showing the buttons; date-fns-tz.
- **Tradeoffs:** 8 s leaves margin on both sides at the cost of a slightly later timeout message.
  Deferring the sign-in page keeps this slice inside its tests.
- **Affects:** R16, R19, R30, R37

## 2026-10-15: OCR pipeline interfaces and scoring rules fixed by the tests

- **Decided by:** agent (test agent, ocr-pipeline)
- **Decision:**
  - `Ocr::Extractor#call(path)` returns an `Ocr::Extraction` (`lines` of `Ocr::Word`s with
    `text` and a 0–100 `confidence`, plus `error`, `text`, `confidence`, `empty?`, `failed?`).
    It never raises: corrupt or missing files and a missing Tesseract binary give a failed
    extraction.
  - `Ocr::FieldMapper.new(threshold:)#call(extraction)` returns an `Ocr::Result` with `fields`
    (always the keys `full_name`, `date_of_birth`, `address`; each `nil` or a reading with `value`,
    `confidence` and `level`), `manual_entry?` and `reason` (`:no_text`, `:low_confidence`,
    `:ocr_error` or `:no_fields`). Dates of birth come back as `YYYY-MM-DD`.
  - One threshold, `OCR_CONFIDENCE_THRESHOLD` on Tesseract's 0–100 scale, does both jobs: an
    overall confidence below it means manual entry (R10), and a field below it is returned but
    marked `:low` (R11). A field at the threshold is `:high`.
  - "Not a guess" (R11) means: a date of birth is taken only from a DOB label, never from issue or
    expiry dates; an impossible or future date is `nil`, not corrected; a label with no value is
    `nil`.
  - The field-level match rules live in `api/eval/README.md`, and the spec runs every row of its
    examples table through `Eval::FieldMatch`, so the docs and the scorer can't drift. Numeric
    dates are read month first; two-digit years never match.
  - R4's 90% applies to each of the three fields, not to their average.
  - Golden set labels are `api/eval/golden/labels.json`, regenerated by the seeded script
    `api/eval/generate_golden_set --out DIR`. Categories are `clean`, `phone_photo`, `skew` and
    `glare`. Fake data is checkable: every address uses state `ZZ` and a ZIP starting `000`.
  - `Eval::OcrScorer.new(golden_dir:, reader:)` takes any callable from image path to field
    values, so the scoring logic is tested without Tesseract, and `rake ai:eval:ocr` (with
    `GOLDEN_DIR`) prints per-field accuracy for all documents, then for hard cases.
- **Alternatives:** a separate high-confidence threshold; scoring the average of the three fields;
  day-first numeric dates; keeping the match rules only in prose.
- **Tradeoffs:** one threshold keeps configuration to the variable the architecture already names,
  but the low/high boundary can't be tuned apart from the manual-entry cutoff. Per-field 90% is
  stricter than an average and may push the implementation toward the PaddleOCR fallback on the
  hard cases.
- **Affects:** R4, R10, R11, R26, R27

## 2026-10-15: OCR preprocessing and Tesseract settings, no PaddleOCR fallback

- **Decided by:** agent (implementation agent, ocr-pipeline)
- **Decision:**
  - `Ocr::Extractor` uses ruby-vips in-process. It resizes to a 1600 px working width, then
    stretches contrast locally: the local paper level (a blur) becomes white and the local ink
    level (a minimum filter) becomes black, both estimated at an eighth of the size. A paper-to-ink
    difference under 60 isn't stretched further, so plain paper noise stays quiet. Then it deskews
    by the row-profile search (whole degrees up to ±6, then quarter degrees) and runs
    `tesseract --psm 11` (sparse text) with TSV output for word confidences. Tesseract's own
    global threshold, applied after the stretch, takes the place of a separate adaptive threshold
    step.
  - The golden set reaches 96.7% name, 100% date of birth and 100% address with Tesseract 5.5.3,
    so the PaddleOCR sidecar fallback isn't built.
  - `Ocr::FieldMapper` compares labels with OCR's common digit-for-letter confusions folded back
    (`1D NO` is the `ID NO` label), and it skips up to two low-confidence tokens in front of a
    label (borders and photo edges read as stray characters). Values are never changed this way.
  - The golden set generator is a Ruby script using ruby-vips. Clean scans are grayscale PNGs and
    the other categories are JPEGs, 75 to 160 KB each and 2.4 MB in total.
- **Alternatives:** dividing by the background only (washed-out text under glare stayed
  unreadable); the default `--psm 3` (merges a middle initial into the first name more often);
  shelling out to the vips CLI (a process and a temporary file per step); PaddleOCR.
- **Tradeoffs:** the stretch sharpens photo-placeholder edges into junk tokens, which the mapper
  has to skip. A fixed working width assumes the card fills most of the photo, so a small card in
  a large photo reads worse. Preprocessing plus Tesseract takes about 0.5 s per image on an
  Apple M2, but Railway's CPU is unmeasured (R23).
- **Affects:** R4, R10, R11, R23, R26

## 2026-10-15: Documents and consent contracts set by the tests

- **Decided by:** agent (test agent, documents)
- **Decision:**
  - **Consent:** `Consent::Ledger.grant!(user_id:, text_version:)`, `.revoke!(user_id:)` and
    `.active?(user_id)`. Each grant is a new `consents` row (`user_id`, `text_version`,
    `granted_at`); revoking sets `revoked_at`, and a later grant makes a new row. A blank version
    raises `ActiveRecord::RecordInvalid`. `POST /consents` with `{ text_version }` returns 201
    `{ consent: { text_version, granted_at } }` for the token's user.
  - **Upload:** `POST /documents` takes a multipart `file`. Every accepted upload returns 200
    `{ document: { id, status: "pending", manual_entry, reason, fields } }`, where `fields` always
    has `full_name`, `date_of_birth` and `address`, each `null` or `{ value, confidence, level }`,
    and `reason` is the `Ocr::Result` reason as a string. OCR failure, an OCR exception, no text,
    low confidence and no fields are all 200 with `manual_entry: true`, never a 500.
  - **Errors:** no active consent is 403 `consent_required`, checked before anything is stored or
    run, and again under a row lock before the draft is written (a revocation during OCR also
    gives 403 and leaves no draft and no stored image). A body over `MAX_UPLOAD_MB` is 413
    `file_too_large`, whose message names the limit; a non-image by content is 415
    `unsupported_file_type`; a truncated or undecodable image is 422 `unreadable_image`; no file is
    400 `invalid_request`. The 413, 415 and 422 envelopes offer `manual_entry`.
  - **Size limit:** the specs call the Rack app with a lazily generated 50 MB body that counts
    what is read. With a declared `Content-Length` over the limit, under 1 MB may be read; with
    no `Content-Length`, reading must stop within 1 MB past the limit.
  - **HEIC is converted, not rejected:** a HEIC upload (recognized by content, whatever its name)
    is converted to JPEG or PNG before OCR and before storage, so the browser can show the
    preview. libvips on the host and the Docker image needs HEIF support (libheif).
  - **OCR seam:** the lifecycle gets its engine from `Ocr::Extractor.new` on each upload and calls
    `#call(path)` with a local copy of the (converted) image; most specs stub `.new`. Two specs
    run real Tesseract on a JPEG and a HEIC of the sample card.
  - **Storage:** the Supabase Storage REST API under `SUPABASE_URL/storage/v1`, bucket
    `STORAGE_BUCKET`, authenticated with `Authorization: Bearer SUPABASE_SERVICE_ROLE_KEY`. The
    specs fake it at the HTTP boundary (`spec/support/fake_supabase_storage.rb`), including its
    400-with-`statusCode: "404"` for a missing object.
  - **Draft and confirm:** OCR output lives only in `document_uploads.draft_fields` (only the three
    fields); `onboardings` gets identity values only from `POST /documents/:id/confirm` (JSON
    `full_name`, `date_of_birth` as `YYYY-MM-DD`, `address`), which saves them as sent with
    `identity_source: "ocr"` and `confirmed_at`, deletes the image from storage and clears the
    draft. A blank field or an impossible or future date is 422 `validation_failed` and changes
    nothing. Other params, such as `identity_source` or `user_id`, are ignored.
  - **Reads:** `GET /documents/:id` returns the pending draft. `GET /documents/:id/preview` signs
    a new URL on every call and returns `{ url, expires_in: 60 }`, with `url` the absolute signed
    URL. After confirm, after purge, or for another user's upload both return 404 and sign nothing.
  - **Manual entry:** `POST /onboarding/identity` with the same three fields saves them with
    `identity_source: "manual"`. It needs no consent record, because no image is involved.
  - **Purge:** `Documents::PurgeExpiredUploadsJob` hard-deletes the storage object and the
    `document_uploads` row for every unconfirmed upload older than 1 hour, tolerates an object
    that is already gone, and is a production task in `config/recurring.yml`.
  - **Filenames:** the uploaded filename appears in no column, storage key, log line or response.
- **Alternatives:** rejecting HEIC with a message (simpler, but iPhone users would hit it often);
  201 for a successful upload and 200 for manual entry; requiring consent for manual entry;
  keeping the purged row with a status.
- **Tradeoffs:** HEIC conversion depends on libheif in every environment, which the CI host's
  Homebrew libvips has. A 200 for every OCR outcome means the web app reads `manual_entry`, not
  the status, to decide what to show. Stubbing `Ocr::Extractor.new` ties the lifecycle to building
  its engine per upload, which is cheap.
- **Affects:** R5, R10, R11, R12, R13, R14, R17, R19

## 2026-10-15: Documents and consent implementation choices

- **Decided by:** agent (implementation agent, documents)
- **Decision:**
  - **Upload order:** consent check, validation, then the `document_uploads` row (pending, no
    draft), then the Storage upload, OCR, and the draft written inside
    `Consent::Ledger.with_active_consent`, which locks the user's active consent rows
    (`SELECT ... FOR UPDATE`). `revoke!` is an `UPDATE` of the same rows, so it waits for an
    in-flight draft write. Any failure after the row exists deletes the image and the row; if
    Storage can't be reached for that delete, the row stays so the purge job retries.
  - **Consent rows:** a grant always adds a row and never touches older ones; `revoke!` ends every
    active row; `active?` is "any unrevoked row". `withdrawn?` (used by chat) is true only for a
    user who consented and now has no active consent, so users who never consented can still
    chat.
  - **Body limit:** a Rack middleware (`lib/boot/upload_body_limit.rb`) on `POST /documents`
    refuses a declared `Content-Length` over `MAX_UPLOAD_MB` plus 64 KB of multipart overhead
    without reading, and copies a chunked body to a temp file 16 KB at a time, stopping as soon
    as it passes that. `Uploads::Validator` then checks the file part against the exact limit.
  - **Validation:** magic bytes for JPEG, PNG and HEIF brands (`heic`, `mif1` and so on), then a
    full libvips decode with `fail_on: :truncated`, and a 100-megapixel cap against decompression
    bombs. JPEG and PNG are stored byte for byte; HEIC becomes a quality-90 JPEG with metadata
    stripped.
  - **OCR reason:** `document_uploads.ocr_reason` holds the `Ocr::Result` reason, because
    `draft_fields` may only hold the three identity fields. `manual_entry` is `ocr_reason.present?`.
  - **Confirm:** runs in one transaction with the upload row locked; the Storage delete happens
    inside it, so a failed delete rolls back the confirmation instead of leaving an image behind.
    A confirmed row is kept with `status: "confirmed"`, no draft and the (deleted) key.
  - **Manual entry** also discards any pending upload the user had, image included.
  - **Storage keys** are `<user_id>/<upload id>.<jpg|png>`. Storage failures map to a 503
    `storage_unavailable` envelope offering `retry` and `manual_entry`.
  - **Purge:** `expires_at` is set to upload time plus 1 hour; the job runs `every hour` and
    deletes pending rows past it, so an image lives under 2 hours at most. The policy is in
    `docs/privacy.md`.
- **Alternatives:** writing the row only after OCR (an image could be orphaned if the cleanup
  delete failed); deleting the image after the confirm commit (it could outlive a confirmation);
  storing the reason inside `draft_fields`; reading the whole chunked body and then checking its
  size.
- **Tradeoffs:** confirm's Storage call inside a transaction holds a row lock for up to the 10 s
  Storage timeout. JPEG originals keep their EXIF metadata in the bucket for their short life,
  because the specs require the stored bytes to match the upload.
- **Affects:** R5, R10, R12, R13, R14, R17

## 2026-10-16: Privacy contracts set by the tests (withdrawal and deletion)

- **Decided by:** agent (test agent, privacy-deletion)
- **Decision:** the privacy-deletion tests fix this contract for the implementer.
  - **Endpoints:** `DELETE /consents` (withdraw consent) and `DELETE /account` (request deletion),
    each 204 with no body, matching the web-identity contract. The user comes only from the token;
    a `user_id` or `id` in the request is ignored, and there is no `/account/:id` route (R19). Both
    are idempotent: a repeat gets 204 again.
  - **Service:** `Privacy::Purger.new(user_id:, storage: Storage::Client.default)` with
    `#withdraw_consent` and `#delete_account`. Both revoke consent through `Consent::Ledger`,
    hard-delete the user's `onboardings` row (draft and confirmed identity), every
    `document_uploads` row (pending and confirmed), the Storage objects behind them,
    `conversations`, `messages` and `assessments`, then write one `audit_events` row. Rows are
    gone, not flagged; the specs count them with plain SQL.
  - **Audit actions:** `consent_withdrawn` and `account_deleted`, with `actor_ref` from
    `AuditEvent.actor_ref_for`. The table keeps exactly `id`, `actor_ref`, `action` and `created_at`.
  - **Deletion only:** also deletes the Supabase Auth user with
    `DELETE <SUPABASE_URL>/auth/v1/admin/users/<id>`, sending the service role key as both
    `Authorization: Bearer` and `apikey`. Withdrawal keeps the Auth user, so the person can still
    sign in and enter details by hand.
  - **Active booking on deletion:** cancelled and the slot freed (it shows in `GET /slots` and
    another user can book it). All of the deleted user's booking rows, active or cancelled, are
    then deleted, so no row keeps a deleted user's ID. **On withdrawal** bookings are kept: a slot
    hold isn't personal data under R13, and the person still has an account.
  - **After revocation:** `GET /documents/:id` and `/preview` return 404. A signed URL issued
    before stops working because the object is deleted (the fake Storage now serves signed URLs
    only while the object exists). Chat with a still-valid token gets a 4xx envelope (403
    `consent_withdrawn` after a withdrawal), makes no LLM call and stores no message. That must
    also hold after deletion, so the implementer can't drop the user's revoked consent rows unless
    something else keeps `withdrawn?` true; a token stays valid until it expires even after the
    Auth user is deleted.
  - **OCR in flight:** OCR runs inside `POST /documents`, not a background job, so "in flight" is
    tested through that request: once with the revocation request sent mid-OCR on the same
    thread, and once on real threads against real Postgres. Either way the upload gets 403 and no
    upload row, draft, identity value or image is left.
- **Alternatives:** keeping a cancelled booking as history after deletion (it would keep the
  deleted user's ID); cancelling bookings on withdrawal too; a soft-delete flag; a background
  purge job with a status endpoint.
- **Tradeoffs:** deleting booking history loses no-show statistics for deleted users. Purging
  synchronously in the request makes it easy to verify, but one Storage call per image makes
  the request slower for a user with many uploads (in practice, one or two).
- **Affects:** R13, R19

## 2026-10-16: Privacy full-flow spec contracts set by the tests

- **Decided by:** agent (test agent, privacy-flow)
- **Decision:** `api/spec/requests/privacy_flow_spec.rb` runs one API-level flow (sign in, chat,
  consent, a real card through real OCR uploaded under a distinctive filename, confirm with every
  value edited, the manual-entry path for a second user, book, reschedule by API and by chat, a
  forced LLM 503, and the purge job) and checks R15 and R20 against what it captured.
  - **Log capture** is `Rails.logger` (which Lograge, ActiveJob and the app write to) at `info`,
    the production level, plus `$stdout` and `$stderr`. A spec pins production's default
    `log_level` to `info`, because debug-level SQL lines would carry chat text.
  - **LLM debug logging** is checked by recording the `@debug_output` of every `Net::HTTP`
    connection that sends a request; all must be nil.
  - **The 503** goes through the real Anthropic adapter to a WebMock stub whose error body echoes
    the request, so a leak of the provider's error body into the logs would carry the payload.
  - **R20 redaction gotcha:** once a user has a confirmed identity (from OCR or typed in), chat
    must build its payload with that identity, so the values typed in a later message, the
    history and the draft reach the LLM as `[NAME]`, `[DATE_OF_BIRTH]` and `[ADDRESS]`. Today
    `Chat::Orchestrator` passes `identity: {}`; the identity source is the user's `Onboarding`.
  - **Fixture:** `spec/fixtures/files/privacy/distinctive_id.jpg` (made by the `make_fixtures`
    script beside it) prints values that appear nowhere else, so OCR-read document data can be
    searched for in logs and payloads separately from the edited values the user confirms.
  - The flow runs once per spec run and its plain-data result is shared by the examples, to
    avoid repeating real OCR 15 times.
  - Frontend log capture is deferred to ESLint `no-console` and the later Playwright slice.
- **Alternatives:** stubbing OCR (would not prove a real image's bytes stay out); capturing at
  `debug` (not what production emits); one example per run of the flow (about 60 s).
- **Affects:** R15, R20

## 2026-10-16: Privacy purge order, kept consent rows and identity source for redaction

- **Decided by:** agent (implementation agent, privacy)
- **Decision:**
  - `Privacy::Purger` revokes consent first, outside the purge transaction, so processing stops
    even if the purge then fails. The row deletes, the Storage deletes and the audit entry run in
    one transaction, so a Storage failure rolls the rows back (503) and a retry finds them; the
    Supabase Auth admin delete runs after the commit, and a 404 from it counts as deleted.
  - The revoked `consents` rows are kept on both withdrawal and deletion. They hold only the user
    ID, the text version and times, and they are what keeps `Consent::Ledger.withdrawn?` true, so a
    still-valid token gets 403 from chat after deletion.
  - Deletion deletes booking rows rather than cancelling then deleting them; with no active row the
    slot is open again.
  - `Chat::Orchestrator` passes the user's confirmed onboarding identity (`identity_source`
    present) to `Llm::PayloadBuilder`, read with `find_by` so chat never creates an onboarding row.
    The data-to-LLM contract is unchanged.
- **Alternatives:** a placeholder consent marker without the user ID after deletion; Auth delete
  inside the transaction (a network call holding row locks, and it can't be rolled back).
- **Tradeoffs:** a deleted user's ID stays in `consents` until their tokens expire and beyond; if
  the Auth delete fails after the commit the user gets 503 and must retry, which repeats the
  (now empty) purge and writes a second audit entry.
- **Affects:** R13, R17, R19, R20

## 2026-10-15: Chat page contract set by the web-chat tests

- **Decided by:** agent (test agent, web-chat)
- **Decision:** `web/src/app/(onboarding)/chat/page.test.tsx` fixes this contract for the
  implementer.
  - The page is the default export of `web/src/app/(onboarding)/chat/page.tsx`. It builds its
    client with `createApiClient({ baseUrl: process.env.NEXT_PUBLIC_API_URL, getAccessToken })`
    and posts `{ message }` (nothing else) to `/chat/messages`.
  - A text field labelled `Message` and a `Send` button. The field is the page's first control,
    Tab from it reaches `Send`, and after sending the field is cleared and keeps focus.
  - The conversation is a `log` region named `Conversation` (polite by default), with each turn
    labelled in text as `You` or `Assistant`. The user's message appears once, even after a retry.
  - Assessment progress is a line of text in one element: "Assessment in progress" until a
    response carries `assessment`, then "Assessment complete" plus a region named
    `Assessment summary` showing reason, urgency, preferred window and notes. The summary stays
    when later replies carry `assessment: null`. The API sends no partial progress, so the page
    can't show per-field progress.
  - The page owns a trigger engine: started on mount (long-pause wired to this step), stopped on
    unmount, fed each 200 response through `reportChatResponse`, and shown with
    `<SupportiveContent>`.
  - A 200 reply is always a normal reply in the log, never an `alert`, the out-of-scope fallback
    included. When its `actions` include `manual_entry`, the page also shows an "Enter details
    manually" button.
  - Errors use `ErrorNotice` ("Try again" resends the same message; "Enter details manually").
    The chat page offers both buttons for every failure that isn't the user's doing: a 503
    envelope and also the client's own `timeout` and `network_error`, which carry only `retry`.
    403 `consent_withdrawn` shows its message with no retry.
  - Continue manually goes to `/identity/manual`: the identity step's manual form, which needs no
    LLM, so the flow carries on without the chat.
  - The page writes no booking or time text of its own; any such statement comes from the reply.
- **Alternatives:** an in-page manual assessment form (no API endpoint exists to save one);
  routing to `/identity`; showing only `retry` on a client timeout, as the envelope says;
  per-field progress inferred from replies.
- **Tradeoffs:** skipping to the identity step means an assessment the chat didn't finish stays
  unsaved; a manual assessment form needs an API endpoint first. Adding `manual_entry` on the
  page for timeouts keeps R16's "try again and continue manually within 10 s" true even when the
  API itself hangs past the client's 8 s timeout.
- **Affects:** R2, R3, R9, R13, R16, R30, R34

## 2026-10-15: Chat page keeps the conversation in memory and never locks the form

- **Decided by:** agent (implementation agent, web-chat)
- **Decision:**
  - The conversation lives in page state only. No endpoint returns past messages, so reloading the
    chat step starts an empty log; the saved assessment is still on the API.
  - `Send` is never disabled. A second send while one is in flight is ignored instead, because
    disabling the focused button would drop keyboard focus (R34).
  - The client's `timeout` and `network_error` get `manual_entry` added in `withManualEntry`
    (`web/src/chat/chatApi.ts`), on the chat step only; the shared API client stays as it is.
  - The "Enter details manually" button for a reply with `manual_entry` follows the latest reply
    and is hidden while an error notice shows its own.
- **Alternatives:** fetching history on mount (no such endpoint); disabling the form while sending;
  adding `manual_entry` to every client-side error in the API client.
- **Tradeoffs:** a reload loses the visible transcript. Changing the client would have offered
  manual entry on steps where it means nothing.
- **Affects:** R2, R16, R30, R34

## 2026-10-15: Schedule page contract set by the web-schedule tests

- **Decided by:** agent (test agent, web-schedule)
- **Decision:** the schedule tests fix this contract for the implementer.
  - `web/src/schedule/Scheduler.tsx` exports `<Scheduler api={ApiClient} />`. It takes the API
    client as a prop, so the tests use the real `createApiClient` with fetch faked at the
    boundary. `web/src/app/(onboarding)/schedule/page.tsx` renders an `h1` "Schedule a call" and
    a `Scheduler` built from `NEXT_PUBLIC_API_URL` (read when the page renders, not at import)
    and `getAccessToken`.
  - On load it calls `GET /slots` and `GET /bookings` and keeps nothing in `localStorage` or
    `sessionStorage` (R8). The booking always comes from the API.
  - **Picker:** a group named "Available times" (a `fieldset` and `legend` with native radios,
    or an ARIA `radiogroup`). Each radio's name is the slot start from `formatLocalDateTime` in
    the browser zone with its zone label (R37). Arrow keys move the selection, the way native
    radios do (R34). A chosen slot also shows as text starting "Selected:". The submit button
    is "Book this time" with no booking and "Move to this time" when rescheduling. With no open
    slots it says "No open times" and shows no button.
  - **Booking:** a region named "Your booking" (a `section` labelled by its heading) shows the
    booked time and the word "Booked", with "Reschedule" and "Cancel booking" buttons. It stays
    visible while rescheduling.
  - **Results:** one `role="status"` element announces "booked", "rescheduled" or "cancelled".
    Errors use `role="alert"`, and there is one alert at a time.
  - **Conflicts (R7):** a `slot_taken` 409 on `POST` or `PATCH` shows the page's own message,
    which contains "just taken". It keeps the picker open, keeps the existing booking, and loads
    `GET /slots` again so the taken slot drops out.
  - **Cancel (R36):** "Cancel booking" asks first ("Cancel your call ..."), with "Yes, cancel
    it" and "Keep my booking" buttons. Nothing is sent until the user confirms. After the cancel,
    the picker returns with the freed slot listed.
  - **Failures:** load errors use `ErrorNotice`, and "Try again" reloads the page data. A missing
    token shows the client's "sign in" message with no retry.
  - `web/src/test-utils/schedulingApi.ts` is an in-memory fake of the scheduling endpoints that
    follows the request specs. `takeSlot` simulates another user booking a slot, and `failNext`
    injects one failure.
- **Alternatives:** a native `<dialog>` for the cancel confirmation (jsdom can't open it
  modally); a listbox instead of radios; pinning exact formatted strings instead of regexes.
- **Tradeoffs:** checking the cancel step with buttons, not a dialog role, leaves the implementer
  free to confirm inline. The time regexes accept any whitespace before AM/PM, because ICU
  versions differ there. A scratch implementation, deleted before commit, passed every test, and
  five mutations of it each failed the tests aimed at them.
- **Deferred:** Playwright e2e for the real sign-in, sign-out and sign-in-again flow (R8 across
  real browser sessions), `@axe-core/playwright` on the deployed page, and color contrast
  (R34), which jsdom can't compute.
- **Affects:** R6, R7, R8, R30, R34, R36, R37

## 2026-10-15: Schedule page refreshes open slots after every change

- **Decided by:** agent (implementation agent, web-schedule)
- **Decision:**
  - `Scheduler` reads `GET /slots` again after every successful book, reschedule or cancel, and
    after a `slot_taken` 409, then shows the new slots, booking and result in one update. The
    page never works out which slots are open on its own; the API is the source of truth (R7,
    R8). If that refresh fails, the old list is shown without the slot just booked or taken.
  - The `role="status"` and `role="alert"` messages render only while they have text, and both
    clear when the user starts the next action (Reschedule, Cancel booking, submit), so a
    screen reader hears each result once and there is never a stale result beside a new one.
  - Cancelling confirms inline inside the "Your booking" region, replacing the Reschedule and
    Cancel buttons with "Yes, cancel it" and "Keep my booking". The submit button is disabled
    until a slot is chosen and while a request is in flight, so a double click can't send twice.
  - The schedule page is a client component that builds its API client once with `useMemo`,
    because a server page can't pass the token function to a client component.
- **Alternatives:** removing the booked slot from the local list (drifts from the API when
  someone else books); an always-present empty live region (announces reliably on more screen
  readers, but leaves an empty status the tests would read as the result); a modal dialog for
  the cancel step.
- **Tradeoffs:** one extra `GET /slots` per change. Conditionally rendered live regions are
  announced by most but not all screen reader and browser pairs; the deferred Playwright and
  axe checks on the deployed page (R34) should confirm it.
- **Affects:** R6, R7, R8, R34, R36

## 2026-10-15: Web identity contracts set by the tests

- **Decided by:** agent (test agent, web-identity)
- **Decision:** the web-identity tests fix this contract for the implementer.
  - **Components** take an `api: ApiClient` (built with `createApiClient`) and callbacks, so the
    tests reach the API only through fetch. `web/src/identity/IdentityStep.tsx` exports
    `IdentityStep({ api, engine, onUploaded(document), onManualEntry })`: the consent form first,
    and the upload form only after `POST /consents` succeeds. `ConfirmIdentityForm({ api,
    documentId, onConfirmed, onManualEntry })` and `ManualIdentityForm({ api, onSaved })` are in
    the same folder; `web/src/privacy/PrivacyControls.tsx` exports `PrivacyControls({ api,
    onDeleted? })`.
  - **Consent (R12):** a region named for consent with "What we collect" and "Why" headings, the
    photo retention, and a visible "Consent text version: <v>" line. The web app owns the text
    and its version and sends exactly the shown `<v>` as `text_version`. The "I agree" checkbox
    starts unticked; "Continue" without it sends nothing. There is no consent lookup endpoint, so
    the identity step always asks again; each grant is a new ledger row, which R12 allows.
  - **Upload (R9, R14):** a native, labeled `input type="file"` ("Photo of your ID") whose
    accessible description names the size limit, `NEXT_PUBLIC_MAX_UPLOAD_MB` or 10 MB by default
    (matching the API's `MAX_UPLOAD_MB`). A file over the limit is refused in the browser with an
    alert naming the limit and isn't sent. The server stays the authority: a 413, 415 or 422
    envelope shows its message in an alert. Every failure (envelope, 5xx, network, the client-side
    size refusal, and a 200 with `manual_entry: true`) calls `engine.reportUpload({ ok: false })`.
    A 5xx or network failure shows `ErrorNotice` with "Try again", which resends the same file; the
    form stays, so no 500 page. A 403 `consent_required` returns to the consent form, unticked.
  - **Manual entry (R10):** a "Skip and enter details manually" button is on the consent, upload
    and confirm forms at all times. `manual_entry: true` shows an alert mentioning manual entry
    and doesn't go to confirm.
  - **Confirm (R5, R11):** the draft comes from `GET /documents/:id`; nothing is posted until the
    user presses the confirm button, then `POST /documents/:id/confirm` gets the form's current
    values. Each field's accessible description is visible text: "needs confirmation" plus "high
    confidence" or "low confidence" for a read field, and "could not read" for a null one, which
    stays empty. A 404 draft shows its message with the skip button.
  - **R13 seam:** no endpoint exists yet, so these tests set it: `DELETE /consents` withdraws
    consent and `DELETE /account` requests deletion, each 204. Each control opens a
    `role="alertdialog"` that explains what is deleted and that it can't be undone, takes focus,
    closes on Escape or "Cancel" (focus back to its button) and sends only on "Yes, ...". The
    result goes in a `status` region ("withdrawn", "deleted"). The privacy page signs the user out
    of Supabase after a deletion, not after a withdrawal.
  - **Pages:** `/identity` pushes `/confirm?document=<id>` after an upload and `/identity/manual`
    on skip, and renders `SupportiveContent` for its own engine. `/confirm` reads the ID with
    `useSearchParams()` and, with none, offers only manual entry. `/confirm` and
    `/identity/manual` push `/schedule` when saved. `/privacy` sits in the `(onboarding)` group,
    outside the step list. Pages build their client from `NEXT_PUBLIC_API_URL` and
    `getAccessToken`.
- **Alternatives:** firing `upload-failure` only for rejected files and not for unreadable ones;
  an upload page that checks consent on load (no endpoint for it); `DELETE /me` or a
  `POST /privacy/requests` job for R13; native `<dialog>` (jsdom lacks `showModal`).
- **Tradeoffs:** asking for consent on every visit adds rows but never uploads without a fresh
  grant. Treating an unreadable photo as a failed upload shows the "try another photo or type it
  in" content exactly when it helps. The R13 paths must be matched by the API slice that builds
  `Privacy::Purger`; the orchestrator should route this entry to it.
- **Affects:** R5, R9, R10, R11, R12, R13, R14, R34

## 2026-10-15: Web identity implementation choices

- **Decided by:** agent (implementation agent, web-identity)
- **Decision:**
  - The consent text and `CONSENT_TEXT_VERSION` live together in `web/src/identity/ConsentForm.tsx`;
    the version is a date and must change whenever the text does. Pressing "Continue" unticked
    shows an alert asking for the tick instead of disabling the button, so the button stays
    reachable and explains itself.
  - `IdentityStep` composes `ConsentForm` and `UploadForm` and owns the single "Skip and enter
    details manually" button below whichever is showing. `ConfirmIdentityForm` and
    `ManualIdentityForm` share `IdentityFields`, so labels, the `YYYY-MM-DD` date hint and the
    reading-status text are written once. Dates are plain text inputs, not `type="date"`, so the
    value typed is the value sent (R5).
  - The 403 `consent_required` upload also fires `upload-failure`, following the contract's
    "every failure" rule. The envelope's `manual_entry` action isn't shown as a second button,
    because the skip button is always present.
  - The privacy confirmation is an inline `role="alertdialog"` that closes as soon as the user
    confirms, so an error or result shows outside it. It doesn't trap focus or set `aria-modal`,
    since the rest of the page stays usable.
  - Pages build their client with a `useApiClient()` hook. `/confirm` wraps its
    `useSearchParams()` reader in `Suspense` for the static build.
- **Alternatives:** a disabled "Continue" until ticked; a native `<dialog>`; `type="date"` inputs.
- **Tradeoffs:** without a focus trap, Tab can leave the open confirmation. The privacy page isn't
  linked from the shell yet, which belongs to the shell owner.
- **Affects:** R5, R9, R10, R12, R13, R34

## 2026-10-16: Web flow contract set by the web-flow tests

- **Decided by:** agent (test agent, web-flow)
- **Decision:** the web-flow tests fix this contract for the implementer.
  - **New API endpoint `GET /onboarding`** (no API slice owns it yet): 200
    `{ onboarding: { step, assessment, identity: { confirmed, source, confirmed_at } } }` for the
    token's user, with `step` one of `chat`, `identity`, `schedule` or `done` (a pending upload
    resumes at `identity`, because the confirm step needs a live document ID), `assessment` the
    saved assessment or `null`, and `source` `ocr`, `manual` or `null`. Identity comes back as a
    status only, never its values. A user with no row gets `step: "chat"`. The web tests fake it
    at fetch; the API needs a request spec and controller for it.
  - **Routing by step:** the web maps `step` to the `STEPS` path, and an unknown step to `/chat`.
    All auth navigation (guard, home, sign-in, sign-out, 401) uses `router.replace`, so Back never
    returns to a page the user can't see.
  - **`/sign-in`** (`web/src/app/sign-in/page.tsx`, outside the `(onboarding)` group): an `h1`
    containing "Sign in" and `SignInForm`. On success it calls `GET /onboarding` and replaces to
    the current step. If that call fails it shows `ErrorNotice`, and "Try again" retries it.
  - **Home `/`:** keeps the "Onboarding assistant" heading; signed out it replaces to `/sign-in`
    without calling the API, signed in it replaces to the current step, and a 401 replaces to
    `/sign-in`.
  - **Auth guard in `(onboarding)/layout.tsx`:** it renders no step content until the Supabase
    session is known. No session, or a session read error, replaces to `/sign-in`.
  - **API 401s:** any `ApiError` with status 401 raised on a step replaces to `/sign-in`: the
    API's 401 envelope (code `unauthorized`) and the client's own missing-token error (code
    `unauthenticated`, status 401) alike, so the web keys on the status, not the code. Tested through the chat page inside
    the layout, so the mechanism must reach pages that build their own client. Other errors stay
    on the page.
  - **Sign-out:** a "Sign out" button in the banner calls `supabase.auth.signOut()` and replaces to
    `/sign-in`.
  - **`/done`** (`web/src/app/(onboarding)/done/page.tsx`): `h1` matching "all set"; reads
    `GET /onboarding` and `GET /bookings`. Regions: "Assessment summary" (or text saying the
    assessment is not saved, with a link to `/chat`), "Your details" (confirmed from the ID photo,
    confirmed from details entered by hand, or not confirmed with a link to `/identity`) and
    "Your booking" (the slot start from `formatLocalDateTime` with its zone label, or "No call
    booked" with a link to `/schedule`). Load errors use `ErrorNotice` with "Try again".
  - **R9 on every step:** the `(onboarding)` layout owns the long-pause trigger, so a step page
    with no engine of its own still shows the long-pause content in a `status` region. On the chat
    step inside the layout each trigger's content appears once, so the layout and the page must
    share one engine (for example through context) rather than each running their own.
  - `web/src/test-utils/flow.ts` holds the shared router mock, session setup and a fetch router;
    it is separate from `test-utils/pages.ts` in the identity MR to avoid a conflict.
- **Alternatives:** deriving the step on the web from `GET /bookings` alone (nothing returns the
  assessment or identity status); keeping the step in `localStorage` (breaks R8 across browsers);
  a `?next=` return path on sign-in; `GET /bookings` folded into `GET /onboarding`.
- **Tradeoffs:** a new endpoint crosses into the API, but it is the only source for the done
  summary and the current step. Keeping bookings on their own endpoint keeps one source of truth
  for R8. Sharing one engine means the chat page (and the identity page in its MR) must take the
  layout's engine, while still working alone in their own tests.
- **Deferred:** Playwright for sign-out and sign-in again across real browser sessions (R8) and
  axe on the deployed pages (R34).
- **Affects:** R8, R9, R19, R30, R34, R37

## 2026-10-16: GET /onboarding contract set by the API request spec

- **Decided by:** agent (test agent, web-flow)
- **Decision:** `api/spec/requests/onboarding_spec.rb` fixes the API side of the endpoint the
  web-flow tests use.
  - `GET /onboarding` needs a token (401 `unauthorized` envelope without one) and returns 200
    `{ onboarding: { step, assessment, identity: { confirmed, source, confirmed_at } } }` for the
    token's user only. A `user_id` param is ignored (R19).
  - **Step is derived, not stored:** from the furthest point reached, `done` with an active
    booking, else `schedule` with a confirmed identity, else `identity` with a saved assessment,
    else `chat`. The unused `onboardings.step` column is not read. Furthest point, not first gap,
    so a user who skipped the chat for manual entry (R16) resumes at `schedule`; the done page
    then says the assessment isn't saved and links to the chat. A pending upload stays at
    `identity`, and a cancelled booking goes back to `schedule`.
  - **New user:** 200 with `step: "chat"`, `assessment: null` and an unconfirmed identity, never a
    404 or 500. The GET is read-only: it creates no `onboardings` row.
  - **Assessment:** the saved `assessments.data` as stored (`reason`, `urgency`,
    `preferred_window`, `distress`, `notes`), or `null`. An unsaved draft in the conversation is
    not returned.
  - **Identity is a status only:** `confirmed` (true when `confirmed_at` is set), `source` (`ocr`,
    `manual` or `null`) and `confirmed_at` as ISO-8601 UTC with `Z`. The name, date of birth and
    address are never in the payload, and neither are their key names. The done page needs only
    the status, so the values have no reason to leave the API again after confirmation (R17).
  - Booking stays on `GET /bookings`; `onboardings`, `assessments` and `bookings` are read, and no
    table is added.
  - The web tests use the API's real 401 code, `unauthorized`, so the web keys on status 401.
- **Alternatives:** storing and advancing `onboardings.step` from each endpoint (several slices
  would each have to write it, and it can drift from the records); first-gap order (sends a user
  who skipped the chat back to it on every sign-in); returning masked identity values.
- **Tradeoffs:** deriving the step costs three small indexed reads per request. The assessment
  `notes` are free text and may mention personal details, but they are the user's own saved
  assessment, already shown to them on the chat step.
- **Affects:** R8, R16, R17, R19

## 2026-10-16: Web flow implementation choices

- **Decided by:** agent (implementation agent, web-flow)
- **Decision:**
  - **401 handling:** `createApiClient` takes an optional `onUnauthorized`, called for any 401
    (the API's or its own missing-token error) before the error is rethrown. The `(onboarding)`
    layout provides a handler through `UnauthorizedContext` that replaces to `/sign-in`, and
    `useApiClient` passes it in. The chat and schedule pages now use `useApiClient` instead of
    building their own client, so every step reaches the handler. Home and sign-in sit outside the
    layout and handle a 401 themselves in `useGoToCurrentStep`.
  - **One trigger engine per step:** the layout creates the engine, keyed on the current step, and
    shares it through `TriggerEngineContext`. `useStepTriggerEngine` returns the layout's engine
    when there is one, or starts the page's own engine when the page renders alone (its own
    tests); the page shows `SupportiveContent` only in the second case. Keying on the step means
    content shown on one step (an upload failure, say) doesn't follow the user to the next, and
    the long-pause timer starts afresh on each step.
  - **Auth guard:** the layout reads the token with `getAccessToken` (a session read error counts
    as signed out) and renders nothing, banner included, until it knows. Sign-out replaces to
    `/sign-in` even if `signOut()` throws, since the local session is cleared either way.
  - **`GET /onboarding`:** `OnboardingsController#show` derives the step from three lookups by
    `user_id` (`Booking.active`, `onboardings.confirmed_at`, `assessments`), with `find_by` so the
    GET never creates a row.
- **Alternatives:** a module-level 401 listener in the client (global state, harder to test);
  one engine for the whole layout (content would carry across steps).
- **Tradeoffs:** pages that render the layout's engine depend on the context to show content;
  rendered alone they fall back to their own, so their existing tests still hold.
- **Affects:** R8, R9, R17, R19, R30

## 2026-10-15: Eval harness interface and how the chat numbers are scored

- **Decided by:** agent (test agent, eval)
- **Decision:**
  - `rake ai:eval` is `Eval::Harness.new(env:, adapter_factory:, ocr_scorer:, results_dir:, out:)`.
    It runs `Eval::OcrScorer` and `Eval::ChatScorer`, prints the scorecard and writes one new JSON
    file per run to `api/eval/results/` (`RESULTS_DIR` overrides). `adapter_factory` takes
    `provider:` and `model:`, so specs inject fake adapters and never reach a real provider.
  - Without `PROVIDERS`, the chat sets run on `LLM_PROVIDER` and `LLM_MODEL`. With `PROVIDERS=all`
    they run on five named candidates: `claude-haiku` (`claude-haiku-4-5`, since there is no
    Haiku 5.5), `claude-sonnet` (`claude-sonnet-5-5`), and `groq`, `gemini` and `ollama` on their
    `Llm::Providers` default models. A candidate whose key (or `OLLAMA_BASE_URL`) is missing is
    reported with `status: "skipped"` and a reason naming the variable, never left out.
  - An intent passes when at least 80% of its labeled utterances route to it
    (`Eval::ChatScorer::INTENT_PASS_THRESHOLD`); intent coverage is the share of intents that pass.
    The schema-valid rate is the share of scripted conversations that end with a saved assessment
    that validates. The out-of-scope fallback rate counts out-of-scope utterances answered with the
    `out-of-scope` intent and adversarial inputs answered without an error or a booking or time
    claim. The "you booked me for Friday" case is reported on its own as `no_false_booking`.
  - p95 latency is the nearest-rank 95th percentile over individual LLM calls, in milliseconds,
    so inputs answered without a call (empty messages) don't dilute it.
  - Cost per conversation is the mean over the scripted conversations of the token cost at the
    per-million-token prices in the committed `api/eval/prices.yml` (keyed by model id). Token
    counts come from a new optional `Llm::Response#usage` (`input_tokens`, `output_tokens`) that
    both adapters fill from the provider's response. Missing usage or a missing price gives an
    unknown (null) cost, never zero.
  - The first 429 stops that provider's run, which is reported with `rate_limited: true`; other
    LLM errors fail only the case they hit.
  - Results files hold only aggregates: no eval message, LLM reply, prompt text, OCR value
    (including misses) or key value.
- **Alternatives:** estimating tokens from characters; timing whole chat messages; retrying after
  a 429; requiring every utterance of an intent to route correctly.
- **Tradeoffs:** stopping at the first 429 understates free tiers that would recover after a
  pause, but it reports the limit honestly instead of hiding it in retries. An 80% bar tolerates
  one miss in five utterances per intent.
- **Affects:** R1, R2, R3, R21, R27, R28

## 2026-10-16: Production LLM provider, Gemini's default model and how failed calls are scored

- **Decided by:** agent (implementation agent, eval)
- **Decision:**
  - Production runs on Claude Haiku 4.5 (`LLM_PROVIDER=anthropic`, `claude-haiku-4-5`) with Groq
    as `LLM_FALLBACK_PROVIDER`. On the 2026-10-16 eval, Haiku matched Sonnet 5.5 on intent
    coverage, schema-valid rate, out-of-scope fallback and no false booking (all 100%) at less
    than half the cost per conversation and a lower p95. Groq was fastest and cheapest but saved a
    valid assessment in only 2 of 3 conversations. The README has the full table.
  - `ARCHITECTURE.md` named "Claude Haiku 5.5", which doesn't exist; it now says Claude Haiku 4.5,
    matching `Llm::Providers` and the eval candidates.
  - The default Gemini model changes from `gemini-2.5-flash` to `gemini-3.8-flash`, replacing that
    part of the 2026-10-15 "LLM client runtime behavior and default models" entry. Google now
    rejects `gemini-2.5-flash` for new API users with HTTP 404 and names `gemini-3.8-flash` as its
    replacement.
  - The eval times only answered LLM calls for p95, and a conversation with no answered call has
    an unknown cost. Failed calls are counted by error class in the results. A run in which every
    call fails therefore reports "n/a" and "unknown", not a fast p95 and a $0 cost.
  - `PROVIDERS` also takes a comma-separated list of candidate names, so one provider can be
    rerun without calling the others again. `rake ai:eval` paces calls per provider
    (`Eval::Harness::FREE_TIER_PACING`) to stay inside free-tier limits; specs run unpaced.
- **Alternatives:** Sonnet 5.5 as primary (perfect routing, about twice the cost and a higher
  p95); Groq as primary (cheapest and free, but a lower schema-valid rate); keeping the retired
  Gemini model and reporting Gemini as failed.
- **Tradeoffs:** Haiku is a paid provider, so production depends on a paid key while the app
  still runs on Groq alone (R21). The eval sets are small: one case moves a rate by 4 to 33
  points. On the free tier, Gemini 3.8 Flash answered no call in two runs 20 minutes apart:
  timeouts at the 6 s client timeout and server errors, then a 429. So it has no usable numbers.
  Ollama (`llama3.2` 3B) ran on a heavily loaded host, which inflates its p95. The first eval run's Gemini entry predates the
  scoring fix and shows $0 and 466 ms where it should show unknown.
- **Affects:** R21, R27, R28

## 2026-10-16: Setup test contract for the seed, the env check and the gates

- **Decided by:** agent (test agent, setup)
- **Decision:**
  - **Schema:** `spec/db/schema_spec.rb` migrates a scratch database (`DATABASE_URL` pointed at
    `api_schema_check_<pid>` on the test server) in a child process, dumps it to a temp file via
    `SCHEMA`, and requires it to equal the committed `db/schema.rb` byte for byte. It also checks
    there are no pending migrations.
  - **Seed:** the one command is `bin/rails db:seed`; the spec runs `Rails.application.load_seed`
    on the empty test database. Demo users are created through the Supabase Auth admin API
    (`POST /auth/v1/admin/users` with `email_confirm: true`), faked at the HTTP boundary by
    `FakeSupabaseAuthAdmin`, which answers a repeat email with 422 `email_exists` as Supabase
    does, so the seed must treat that as "already there". Credentials are fixed (the same on
    every run), use reserved domains (`example.com/org/net` or `.test`), and are printed on every
    run.
  - **Golden set "registered":** there is no golden-set table, so registered means the seed
    validates `eval/golden/labels.json` (or `GOLDEN_DIR`, as `ai:eval:ocr` uses) and prints a
    line naming the golden set and its document count; it raises, naming the golden set, when the
    set is missing.
  - **Env check:** `bin/check-env [ROOT]` at the repo root. Fails on a variable read in app code
    but not in its own app's `.env.example` (API code against `api/.env.example`, web code
    against `web/.env.example`), and on one listed without a comment above it in the same block.
    `api/spec`, `*.test.*`, `node_modules` and `.next` aren't scanned. Unused variables in an
    example aren't flagged.
  - **Gates:** a static spec reads `bin/gates` and requires uncommented lines calling
    `bin/check-env` and `gitleaks git`.
- **Alternatives:** a golden-set database table (not in the architecture); comparing schema.rb
  against `db:schema:dump` of the test database (it would pass a schema.rb loaded rather than
  migrated); flagging stale example entries (would force removing optional runtime settings).
- **Affects:** R32, R33

## 2026-10-16: Local setup, the seed and the env check

- **Decided by:** agent (implementation agent, setup)
- **Decision:**
  - **Local stack:** the Supabase CLI runs only Auth, Storage and the API gateway
    (`supabase/config.toml` disables Studio, Realtime, Edge Functions, analytics and mail). The
    API's own tables stay in the docker compose Postgres, as in tests, so dev and test share one
    database setup. Auth signs with a local ES256 key (`supabase/signing_keys.json`, generated by
    `bin/setup`, gitignored) because the API rejects HS256 tokens, which is what the CLI issues by
    default.
  - **`bin/setup` at the root** checks the system dependencies, installs packages, starts both
    stacks, writes `api/.env` and `web/.env.local` from the examples with the local Supabase URL
    and keys and random encryption and HMAC keys, then migrates and seeds. It never overwrites an
    existing env file. The API runs natively (not in docker compose) so Tesseract and libvips come
    from the host, as in CI.
  - **dotenv in development only:** the API loads `api/.env` with the `dotenv` gem in the
    development group. Not in test, so specs never pick up real keys.
  - **Seed:** `Seeds::DemoData` checks the golden set before writing anything, then
    `find_or_create_by!` slots at fixed UTC hours on weekdays over the next 14 days (so a later
    run adds new future slots but never duplicates), then creates two fixed demo users through
    `Auth::AdminClient#create_user`, which treats 422 `email_exists` (or the older "already been
    registered" message) as already there. The password is fixed and printed so the README can
    list it.
  - **Gates:** the test database step is `db:create db:schema:load`, not `db:prepare`, because
    `db:prepare` runs the seed on a new database, which would call Supabase Auth in CI.
  - **Env check scope:** `bin/check-env` finds direct reads only (`ENV[...]`, `ENV.fetch`,
    `ENV.key?`, `process.env.X`, `process.env["X"]`), skips comment lines and jest config, and
    ignores `BUNDLE_GEMFILE` and `CI`, which the toolchain sets. Variables read through a passed-in
    hash (`env["LLM_PROVIDER"]` in `Llm::Client`) aren't found; they are listed in the example by
    hand. Matching lowercase `env[...]` would flag Rack request keys.
  - **Local port:** `PORT` in `api/.env.example` is 3001, so the API runs beside the web app on
    3000 and matches `NEXT_PUBLIC_API_URL`. Railway sets its own `PORT`.
- **Alternatives:** the API's tables in the Supabase local Postgres (one fewer container, but a
  different server from tests and CI); running the API and web in docker compose (needs a dev
  image with Tesseract, slower first run); asking for a token in setup instead of writing env
  files.
- **Affects:** R32, R33
