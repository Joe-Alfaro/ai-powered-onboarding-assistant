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
