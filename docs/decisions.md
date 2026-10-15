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
    403 `consent_withdrawn`, with no LLM call and nothing saved.
  - **Endpoint:** `POST /chat/messages` with `{ message, booking_id?, slot_id? }` returns
    `{ reply, intent, trigger, actions, assessment, scheduling }`. A missing message is treated as
    empty (200 with a reply, not 400). LLM failures return 503 with the `Llm::Error`'s `code`,
    a message and `actions: ["try_again", "continue_manually"]`, the merged `Llm::Error::ACTIONS`.
  - **Eval sets:** `api/eval/chat/intents.yml` (at least 5 labeled utterances per intent),
    `conversations.yml` (scripted turns with the fake LLM's output and the expected record) and
    `adversarial.yml`. The specs and the eval harness (R27) share them.
- **Alternatives:** gating chat on `Consent::Ledger.active?` as ARCHITECTURE says; requiring the
  LLM to supply `distress` and `notes`; putting the slot time in the reschedule reply text;
  `retry` and `manual_entry` action names.
- **Tradeoffs:** the onboarding flow has chat before consent, so `active?` would block every new
  user's first message; `withdrawn?` still stops all LLM calls after revocation (R13), and the
  consent slice must provide it. Defaults for `distress` and `notes` let real providers that omit
  them still complete an assessment. Keeping times out of reply text keeps the guard simple and
  local-time display in one place. The action names follow the merged LLM client rather than
  introducing a second set.
- **Affects:** R1, R2, R3, R9, R13, R16, R36
