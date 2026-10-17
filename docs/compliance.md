# Compliance

## No service domain is assumed

The app is domain-neutral. It onboards a person (ID upload, a short assessment in chat, an
appointment) without assuming what the service behind it is, and no regulatory regime is assumed
to apply. This document names the two regimes most likely to apply if the app were used in a
regulated domain, says how the current design supports each, and lists what this free-tier demo
still lacks. **The demo is not compliant with either regime, and makes no claim to be.**

- **Healthcare:** HIPAA (the US Health Insurance Portability and Accountability Act), if a covered
  entity or business associate used the app to onboard patients. The assessment (reason for
  seeking the service, urgency, distress) and the chat transcript would then be protected health
  information, alongside the identity details.
- **Financial services:** PCI DSS (the Payment Card Industry Data Security Standard), if the app
  were used to onboard customers and took card payments, or came to store, process or transmit
  card data.

## Design controls both regimes rely on

Each control below is implemented and covered by the test suite. The linked documents give the
detail.

| Control | What the app does |
| --- | --- |
| Consent ledger | No image is uploaded or processed before the user agrees to the consent text. Each grant records the text version shown and the time; a grant is never edited except to record its revocation (`Consent::Ledger`). Withdrawal stops processing before anything is deleted. |
| Data minimization | OCR keeps only full name, date of birth and address from the card, as a draft. Nothing else on the card is stored. The uploaded filename is discarded and HEIC metadata stripped. |
| Short image retention | ID images are deleted when the user confirms their details, or by an hourly job within 2 hours if they never do ([privacy.md](privacy.md)). |
| Hard deletion | Withdrawing consent or deleting the account deletes rows, not flags: identity, drafts, images in Storage, the conversation, messages and the assessment. Account deletion also deletes bookings and the sign-in account. |
| Audit log with pseudonymous IDs | Consent withdrawal, account deletion and every admin access write an `audit_events` row whose actor is a keyed HMAC of the user ID (`AUDIT_HMAC_KEY`), with no name, email or user ID. |
| Encryption | HTTPS in transit, provider disk encryption (AES-256) at rest, and app-level Active Record encryption of identity fields, OCR drafts, chat content and assessments ([security.md](security.md#encryption)). |
| No images to an LLM | Image bytes go only to Tesseract, which runs inside the API container. The LLM payload builder accepts plain text only and rejects image data. |
| Data-to-LLM allowlist | `Llm::PayloadBuilder` sends only recent message text and the assessment draft, with confirmed identity values replaced by placeholders. A contract spec checks the real request body against [data-to-llm.md](data-to-llm.md). |
| RLS deny-all | Row-level security is on for every `public` table with no policy for client roles, so a leaked anon key reads nothing. |
| Server-side access control | The API takes the user only from the verified sign-in token and scopes every query to them. The browser never reads the database. Admin endpoints require the `admin` role from `app_metadata`. |
| No secrets or bodies in logs | Logs are single-line JSON. LLM request and response bodies are never logged, and error entries name the exception class without its message. |

## HIPAA

### How the design supports it

- **Minimum necessary:** data minimization and the data-to-LLM allowlist limit what is collected
  and what leaves the app. Identity values are redacted before any LLM call.
- **Access control (Security Rule, technical safeguards):** server-side access control scoped to
  the token's user, RLS deny-all, and an admin role users can't grant themselves.
- **Audit controls:** admin access and every withdrawal and deletion are recorded, without putting
  personal data in the log.
- **Transmission security and encryption:** HTTPS everywhere, provider encryption at rest and
  app-level encryption of every column that would hold protected health information.
- **Disposal:** hard deletion and the short image retention leave no copy behind in the app's own
  database or bucket.
- **Patient rights:** a user can withdraw consent or delete their account in the app, and the
  effect is immediate.

### What the free-tier demo lacks

- **No business associate agreements (BAAs).** None has been signed with Supabase (database, Auth,
  Storage), Railway (hosting) or any LLM provider (Anthropic, Groq, Gemini). Without a BAA, none of
  them may receive protected health information. Supabase offers a BAA only on paid plans with its
  HIPAA add-on, and free-tier LLM APIs are not covered by one.
- **No formal risk analysis** or risk management plan, which the Security Rule requires.
- **No administrative safeguards:** no security officer, workforce training, policies, sanctions
  or incident response and breach notification procedure.
- **Audit coverage is partial.** Ordinary reads of a user's own data, and the API's own access to
  the database, aren't logged per record, and audit entries have no retention or tamper-evidence
  policy.
- **No contingency plan:** no tested backup restore, disaster recovery or emergency mode, beyond
  whatever the free tiers provide.
- **No retention limit for chat and assessments.** They are kept until the user withdraws consent
  or deletes their account. A real deployment would need a documented retention schedule.
- **Redaction is best-effort.** Only identity values the user has already confirmed are replaced,
  in the formats listed in [data-to-llm.md](data-to-llm.md). Other health details the user types
  go to the LLM provider by design, which is exactly why a BAA would be required.
- **No key management service.** Encryption keys are environment variables on Railway, with no
  rotation procedure.

## PCI DSS

### Scope today

The app takes no payments, has no card fields and stores no cardholder data, so as built it is
outside PCI DSS scope. PCI DSS would apply only if card data entered the system.

### How the design supports it

- **Keeping card data out** is the most effective PCI control. If payments were added, the design's
  pattern (the API stores only what it needs, and the allowlist decides what reaches a third party)
  points to a hosted payment page or tokenizing processor, so card numbers never touch the API.
  That keeps the app's own scope to the smallest self-assessment.
- **Requirements 3 and 4 (protect stored data, encrypt in transit):** app-level encryption, provider
  encryption at rest and enforced HTTPS.
- **Requirements 7 and 8 (restrict access, identify users):** per-user scoping from the verified
  token, RLS deny-all and an admin role outside the user's control.
- **Requirement 10 (log access):** pseudonymous audit entries for admin access, withdrawals and
  deletions, and structured JSON logs with no request bodies.

### What the free-tier demo lacks

- **No card data detection in chat.** A card number typed into chat would be stored (encrypted) in
  the message and sent to the LLM provider inside the message text, because redaction covers only
  identity values. A real deployment would need to detect and reject or mask card numbers before
  storage and before any LLM call.
- **No scoping or assessment:** no cardholder data environment diagram, self-assessment
  questionnaire, quarterly vulnerability scans or penetration test.
- **No service provider attestations collected** from Supabase, Railway or the LLM providers.
- **Partial logging:** PCI DSS expects every access to cardholder data and every admin action to
  be logged, reviewed daily and kept for a year. The audit log has no review process or retention
  policy.
- **No multi-factor authentication** for admins, and no key management or rotation procedure.

## Before using the app in a regulated domain

At minimum: decide the domain and the regimes that apply, sign BAAs (or collect PCI attestations)
with every vendor that would see the data or move to vendors that offer them, run a formal risk
assessment, add the missing logging, retention and key management, and get an independent review.
