# Onboarding Assistant: Requirements

## Goal

An AI-powered onboarding assistant for people registering for a specialized, potentially sensitive
service. It cuts data entry and stress: an LLM chatbot guides the user and produces an initial
assessment, a photo of an ID pre-fills the form, a scheduler books the next appointment, and
supportive content appears where users tend to give up.

**Target user:** a person signing up for a specialized, possibly sensitive service who wants to
finish onboarding quickly, with minimal typing and minimal stress.

**Service domain:** not specified, and none is assumed. The app is domain-neutral. R20 covers how
it would support the regimes that apply if it's used for healthcare or financial services.

## How to read this file

- Every requirement has an ID and one or more **done checks**. The work is done when every done
  check passes.
- **Gotchas** are requirements, or done checks within one, that are easy to get almost right. They
  are tagged **[gotcha]** and indexed in [Gotcha index](#gotcha-index).
- "Personal data" means identity fields (name, date of birth, address), document images, and chat
  transcripts that contain any of them.
- Defined lists referenced by done checks:
  - **Intent list:** `provide-details`, `ask-question`, `request-reschedule`, `express-distress`,
    `out-of-scope`.
  - **Required assessment fields:** listed in the committed assessment schema (R2). At minimum:
    the reason for seeking the service, urgency, preferred appointment window, and a
    distress flag.
  - **Supportive-content triggers:** `long-pause`, `upload-failure`, `high-stress-intent`, each
    with a threshold and mapped content in a committed trigger table. The long-pause threshold is
    configurable with a documented default.

## Core features

### R1. Chatbot handles every intent

A conversation gathers the onboarding information the service needs.

- [ ] For each intent in the intent list, the committed intent set has labeled example utterances,
      and the chatbot routes each one to the handler for that intent.
- [ ] The AI eval harness (R27) reports pass for every intent in the list.

### R2. Chatbot produces a structured assessment

- [ ] A committed schema defines the assessment record and its required fields.
- [ ] Running each committed scripted conversation produces a record that validates against the
      schema, with every required field populated; the eval reports a 100% schema-valid rate.
- [ ] **[gotcha]** LLM output that is malformed or missing fields is validated and repaired or
      retried; it never reaches the database unvalidated.
- [ ] The record is saved to the user's onboarding record and shown to the user as a summary.

### R3. Chatbot falls back gracefully and makes no made-up commitments

- [ ] Out-of-scope or unrecognized input returns a polite redirect to the onboarding task, not an
      error, and the conversation can continue.
- [ ] **[gotcha]** Empty input, a 10,000-character message, emoji-only input and a prompt-injection
      attempt ("ignore previous instructions…") each get a fallback reply, not an error.
- [ ] **[gotcha]** The chatbot never claims a booking, time, diagnosis or outcome that isn't backed
      by stored data. Any booking or time it states comes from the scheduler's structured result,
      not free LLM text; an eval case checks this.

### R4. Photo of an ID pre-fills the form

- [ ] Uploading a document image returns extracted name, date of birth and address.
- [ ] On the OCR golden set (R26), field-level accuracy is at least 90% across all three fields,
      as reported by the eval harness.
- [ ] **[gotcha]** The docs define "field-level match" precisely: the normalization applied before
      comparing (case, whitespace, date formats, address abbreviations). The harness uses exactly
      that definition.

### R5. Extracted fields are confirmed before saving

- [ ] Every extracted field is shown in an editable form before anything is saved.
- [ ] **[gotcha]** After an upload and before confirmation, the onboarding record contains no
      extracted values (only a pending draft); an API test shows that skipping confirmation saves
      nothing.
- [ ] Values the user edits are saved as edited.

### R6. User can view and book an appointment

- [ ] A signed-in user sees open slots.
- [ ] Booking a slot returns and displays a confirmation with the slot's date and time.
- [ ] A booked slot no longer appears as open.

### R7. Double-booking is rejected, including under concurrency **[gotcha]**

- [ ] Booking a slot that is already booked is rejected with a clear message, and the original
      booking is unchanged.
- [ ] 20 parallel requests for the same open slot produce exactly 1 booking; the other 19 get a
      clear rejection (409).
- [ ] The database enforces it (a unique constraint or row lock), not only application code.

### R8. Bookings persist across sessions

- [ ] After signing out and back in (or from a new browser), the user sees their booking.

### R9. Supportive content appears at the right moments only **[gotcha]**

- [ ] Each trigger in the trigger table shows its mapped content: `long-pause` after the configured
      inactivity threshold on an onboarding step, `upload-failure` after a failed or rejected
      upload, and `high-stress-intent` when the chatbot classifies a message as `express-distress`.
- [ ] The long-pause timer doesn't fire while the user is typing or the tab is hidden.
- [ ] With no trigger met, no supportive content is shown. A test drives the full happy path and
      asserts none appears.
- [ ] Whether content shows is decided by the trigger table, never by the LLM's discretion.

### R36. User can reschedule or cancel a booking **[gotcha]**

The `request-reschedule` intent can't be handled truthfully without this.

- [ ] A user can move their booking to another open slot, or cancel it, from the scheduler and
      through the chatbot.
- [ ] After a reschedule or cancellation, the old slot is open again and the database reflects the
      change.
- [ ] The chatbot's reschedule reply reflects the real result (R3).

### R37. Slot times are correct across timezones **[gotcha]**

- [ ] Slot times are stored in UTC.
- [ ] A user in a different timezone from the server sees slots and confirmations in their local
      time, labeled with the timezone.

## Edge cases and failure modes

### R10. OCR failure falls back to manual entry

- [ ] When OCR returns nothing, returns confidence below the configured threshold, or throws, the
      user is offered manual entry for all fields.
- [ ] A user can finish onboarding without uploading any image.
- [ ] None of these cases return a 500.

### R11. Partial extraction is shown without fabrication **[gotcha]**

- [ ] When OCR reads only some fields, those are pre-filled and visibly marked as needing
      confirmation (marked by text or icon, not color alone), and the missing fields are blank.
- [ ] A field that OCR didn't read is never filled with a guessed or LLM-generated value.
- [ ] Low-confidence fields are marked differently from high-confidence ones.

### R12. Consent is captured before any upload **[gotcha]**

- [ ] Before the upload step, the user sees what is collected and why, and must give explicit
      consent. The consent control isn't pre-selected.
- [ ] The upload endpoint, called directly with a valid token but no consent record, returns 403
      and stores and processes nothing.
- [ ] Each consent is stored with the user, a timestamp, and the version of the consent text.

### R13. Consent revocation and deletion are honored **[gotcha]**

- [ ] A user can withdraw consent or request deletion from the app.
- [ ] Afterwards, their document images and extracted personal data are hard-deleted from the
      database and storage (no soft delete), and requests to retrieve them return not found.
- [ ] Signed URLs issued before the revocation no longer work.
- [ ] Processing stops: an OCR job in flight at revocation writes nothing afterwards, and later chat
      messages make no LLM call (verified by counting calls to a stubbed provider).
- [ ] The revocation or deletion is recorded in an audit log entry with only a pseudonymous ID,
      the action, and a timestamp.

### R14. Bad uploads are rejected **[gotcha]**

- [ ] The server checks file type by content, not just extension, and enforces a documented size
      limit before reading the whole file into memory.
- [ ] A renamed non-image file, a truncated or corrupt image, and an oversized file each get a
      clear user-facing 4xx message, are not processed, and don't crash a worker.
- [ ] HEIC phone photos are either converted and processed or rejected with a clear message.

### R15. No personal data in logs **[gotcha]**

- [ ] Application logs, error traces and analytics events never contain extracted identity fields,
      image data, uploaded filenames, chat message text, or LLM prompts.
- [ ] Rails parameter filtering covers name, date of birth, address, message, image and transcript
      fields, and LLM client debug logging is off.
- [ ] An automated test runs the full flow with distinctive synthetic values and asserts none of
      them appear in the captured backend and frontend log output.

### R16. LLM failure degrades gracefully

- [ ] Every LLM call has a client timeout.
- [ ] When the LLM provider times out, returns a 5xx or 429, or is unreachable, the user gets a
      clear "try again" and "continue manually" choice within 10 s.
- [ ] No hang, no unhandled error, and no made-up commitment in these cases.
- [ ] Tests cover timeout, 5xx, 429 and connection failure using a stubbed provider.

## Security and privacy

### R17. Document images are stored privately and discarded by default

- [ ] Images are kept only in a private bucket and are reachable only through short-lived signed
      URLs; no public URL exists.
- [ ] After the user confirms extracted fields, the source image is deleted, and a check shows it
      no longer exists in storage.
- [ ] **[gotcha]** Images from abandoned, never-confirmed uploads are purged by a scheduled job
      after a documented time-to-live. A test uploads, never confirms, advances time, and finds
      the image gone.
- [ ] The retention and deletion policy is written in the docs.
- [ ] Only the fields the flow needs are stored.

### R18. Data is encrypted in transit and at rest

- [ ] The deployed app is served only over HTTPS.
- [ ] The database and image storage use encryption at rest, and the docs say how.

### R19. Users can only access their own data **[gotcha]**

- [ ] Authentication uses Supabase Auth, and the API identifies the user from the verified token,
      never from a user ID in the request.
- [ ] As user A, requesting user B's onboarding record, booking or image by ID returns 403 or 404.
- [ ] Row-level security is enabled on any table the frontend reads directly from Supabase.
- [ ] Every staff or admin endpoint (for example slot management) rejects non-admins, and each
      admin access writes an audit log entry.

### R20. Data sent to AI providers is minimal and documented **[gotcha]**

- [ ] Image bytes go only to the self-hosted OCR engine; no vision LLM or cloud AI service ever
      receives a document image.
- [ ] A committed document lists exactly which personal-data fields are sent to each LLM provider,
      and why each is needed.
- [ ] A contract test captures the outgoing LLM payload and asserts its personal-data fields match
      that document exactly.
- [ ] The docs state that no service domain is assumed, name the regimes that would apply if the app
      were used for healthcare (HIPAA) or financial services (PCI DSS), and say how the design
      supports each and what a free-tier demo would still lack (for example vendors without a
      BAA).

### R21. No paid API is required **[gotcha]**

- [ ] The app runs on a free LLM provider selected by an environment variable, with no code
      changes.
- [ ] With only free or local provider keys set, the eval harness completes on the free provider
      and skips missing providers with a message instead of crashing.

## Performance

### R22. Chatbot and API respond in under 3 s at p95

- [ ] A committed k6 script runs 20 virtual users for 60 s against the chatbot and API.
- [ ] The reported p95 is under 3.0 s with an error rate near 0, and the result is recorded in the
      docs.
- [ ] The docs state whether the chat path in the k6 run hit the real LLM.

### R23. OCR extraction finishes in under 8 s at p95

- [ ] Over 20 runs, the time from upload receipt to the extracted-fields response is under 8.0 s at
      p95, and the result is recorded in the docs.
- [ ] **[gotcha]** The measurement is taken on the deployed environment, and the docs say how it
      was timed.

### R24. Booking finishes in under 1 s at p95

- [ ] Every booking request logs its server time.
- [ ] Over 20 runs, that time is under 1.0 s at p95, and the result is recorded in the docs.

### R25. Deployed demo uptime is at least 99%

- [ ] An uptime check pings the deployed health endpoint on a schedule, and the measured uptime
      over the evaluation window is at least 99%.

### R38. Performance holds on the deployed app, not just locally **[gotcha]**

Free tiers sleep, pause and rate-limit, which can break R22–R25 only after deployment.

- [ ] The k6 run in R22 targets the deployed URL.
- [ ] After 30 minutes idle, the first request to the deployed app responds in under 3 s.
- [ ] The database stays active through the evaluation window (the uptime ping touches it).
- [ ] LLM rate-limit responses (429) under load are handled as in R16, and the docs report how many
      occurred.

## AI evaluation

### R26. Synthetic OCR golden set

- [ ] 30 synthetic labeled documents are committed, each with expected name, date of birth and
      address.
- [ ] The set includes clean scans, phone photos, and mild skew and glare, with at least 3 hard
      near-miss cases labeled as such.
- [ ] No document contains real personal data.

### R27. Eval harness prints a scorecard

- [ ] One committed command runs the OCR golden set and the intent set and prints per-field OCR
      accuracy and per-intent pass/fail, with hard cases reported separately.
- [ ] The docs record the model versions, the OCR engine version, and the hardware used.

### R28. LLM providers are compared and the choice is justified

- [ ] The harness runs unchanged against each candidate provider: Claude (Haiku and Sonnet), Groq,
      Gemini and Ollama.
- [ ] The docs report each provider's intent coverage, schema-valid assessment rate,
      out-of-scope fallback, p95 latency, cost per conversation, and whether rate limits cut the
      run short. No provider is left out.
- [ ] The docs name the production provider and justify it against those numbers.

## Engineering practices

### R29. Core logic has at least 80% test coverage

- [ ] Coverage reports show at least 80% for OCR extraction and mapping, chatbot orchestration, and
      scheduling state.

### R30. Every main dependency fails gracefully **[gotcha]**

- [ ] With the OCR engine, LLM provider, database, or network down, the user sees a clear message
      and a retry or manual path within 10 s.
- [ ] The demo flow returns no unhandled 500s and no silently wrong results; neither the Rails API
      nor Next.js shows a default error page.

### R31. Structured logs and a health endpoint

- [ ] Errors are logged as structured entries with no personal data.
- [ ] A health endpoint reports the status of the app, database, OCR engine and LLM provider.
- [ ] **[gotcha]** Breaking any one dependency changes its status in the response. The LLM check is
      a cheap or cached probe that doesn't spend free-tier quota on every ping.

### R32. Runs from a clean checkout **[gotcha]**

- [ ] Schema changes are committed migrations.
- [ ] One seed command loads slots, demo users and the golden set.
- [ ] Following only the README on a fresh machine or container gets the app running, seeded, and
      through the tests and eval harness in about 15 minutes, including system dependencies like
      the OCR engine.

### R33. Configuration comes from the environment

- [ ] No secrets are committed; a secret scan of the repo and its history is clean.
- [ ] `.env.example` lists and explains every environment variable the app reads, and a check
      compares the variables referenced in code against it.

### R34. Accessibility baseline

- [ ] Every flow works with the keyboard alone, including the chat, file picker and slot picker.
- [ ] Every form control has a label.
- [ ] Text and controls meet WCAG AA color contrast.
- [ ] No status is shown by color alone.
- [ ] An automated accessibility check (such as axe) reports no serious or critical violations on
      the main pages.

### R35. CI runs tests, linters and coverage on every push

- [ ] CI runs RSpec, Jest, RuboCop and ESLint on every push to any branch, and fails the build if
      any fail.
- [ ] **[gotcha]** CI fails if coverage on the R29 modules drops below 80%.

## Stretch (optional)

Not required for done. Pursue only after every R above passes, and only with the user's go-ahead.

- **S1. Multiple languages:** chatbot and supportive content in at least 2 languages.
- **S2. Sentiment-adaptive tone:** detect stress or sentiment and adapt tone and pacing.
- **S3. Analytics dashboard:** funnel drop-off, per-step completion time, and OCR correction rates.
  If built, it is admin-only (R19) and stores no personal data (R15).

## Out of scope

- Real identity verification (checking an ID is genuine), payments, and staff-side case
  management beyond what R19 needs.
- Cloud OCR.
- Meeting the illustrative business metrics (completion rate, NPS). They guide design but aren't
  measured. The demo video does show a full onboarding finishing well under 15 minutes.

## Gotcha index

| Gotcha | Where |
| --- | --- |
| Free-tier sleep, pause and rate limits break deployed performance and uptime | R38, R23, R31 |
| Double-booking race under concurrency | R7 |
| Supportive content shown without a trigger, or a vague pause trigger | R9 |
| Extracted values saved before confirmation, or fabricated | R5, R11 |
| Deletion that isn't verifiable (soft delete, leftover storage, live signed URLs, in-flight jobs) | R13 |
| Consent enforced only in the frontend, or pre-ticked | R12 |
| Personal data leaking through Rails params, filenames, LLM debug logs or frontend logs | R15 |
| ID images sent to a vision LLM; disclosure document not matching the payload | R20 |
| "Field-level accuracy" undefined; golden set without hard cases | R4, R26, R27 |
| `request-reschedule` intent with no reschedule feature behind it | R36 |
| LLM claiming bookings or outcomes that don't exist | R3 |
| Missing timeouts; database-down and default error pages | R16, R30 |
| Upload validation by extension only; corrupt images crashing OCR; HEIC | R14 |
| Images from abandoned uploads kept forever | R17 |
| API trusting a user ID param; missing RLS; unaudited admin | R19 |
| Eval or app requiring a paid key | R21 |
| Clean checkout missing system dependencies or env vars | R32, R33 |
| Coverage not enforced in CI | R35 |
| Malformed LLM output and hostile input | R2, R3 |
| Compliance regime skipped, or claimed without stating free-tier gaps | R20 |
| Slot times wrong across timezones | R37 |
| Company names leaking into the repo, deployment or video | Deliverables |

## Deliverables

Checked at submission, not part of the build audit.

- [ ] Public GitLab repository
- [ ] README: what the app does, stack and LLM choices with reasons, the grader quick-start (setup,
      environment variables, seed command, demo credentials, test and eval commands), and the
      performance and eval results with how each was measured
- [ ] `AI_USAGE.md`: AI tools used and for what, LLM and OCR engines and versions, and prompts or
      configuration that shaped the solution
- [ ] `ARCHITECTURE.md` and other technical documentation, including the data-to-LLM document (R20)
- [ ] Committed seed script, fixtures, synthetic golden set, `.env.example` and k6 script
- [ ] Deployed app URL on Railway
- [ ] Demo video showing the chatbot flow, ID upload with confirmation, a booking, supportive
      content appearing, and at least one failure path
- [ ] **[gotcha]** No company or program names anywhere in the repo, its history, the deployment or
      the video
