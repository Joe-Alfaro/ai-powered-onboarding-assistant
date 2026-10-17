# Security

How the app protects personal data in transit and at rest (R18), and who can reach it (R19).
[privacy.md](privacy.md) covers retention and deletion, [data-to-llm.md](data-to-llm.md) covers
what reaches an LLM provider, and [compliance.md](compliance.md) covers regulatory regimes.

## Encryption

Personal data is encrypted twice at rest: once by the hosting providers at the disk level, and
once by the API itself, column by column, before it is written to the database.

### In transit

- **Browser to the app.** In production the web app and the API run on Railway, which serves every
  public domain over HTTPS with a certificate it provisions and renews automatically (Let's
  Encrypt), and redirects plain HTTP requests to HTTPS
  ([Railway public networking](https://docs.railway.com/networking/public-networking)).
- **The API enforces it too.** `api/config/environments/production.rb` sets `config.force_ssl =
  true` and `config.assume_ssl = true`: Rails redirects any non-HTTPS request, sends a
  `Strict-Transport-Security` header and marks cookies secure.
- **The API to Supabase Auth and Storage.** The API calls the Supabase project at `SUPABASE_URL`,
  which is an `https://` URL in production. Image uploads, downloads, signed URLs and deletions all
  go over it.
- **The API to the database.** The API connects to Supabase Postgres with `DATABASE_URL`.
  Postgres clients negotiate TLS by default when the server offers it, and Supabase does. The app
  doesn't pin `sslmode=require` itself; set it in `DATABASE_URL`, or turn on SSL enforcement in the
  Supabase project, to refuse unencrypted connections outright.
- **The API to LLM providers.** Anthropic, Groq and Gemini are called over HTTPS
  (`api/app/services/llm/adapters/anthropic.rb`, `api/app/services/llm/providers.rb`). Ollama is
  a local server reached at `OLLAMA_BASE_URL`, plain HTTP on `localhost` by default.

### At rest: provider disk encryption

The production database and image storage are Supabase Postgres and a private Supabase Storage
bucket (`STORAGE_BUCKET`). Supabase documents that all customer data is encrypted at rest with
AES-256, including backups, with per-project keys protected by FIPS 140-2 compliant hardware
security modules ([Security at Supabase](https://supabase.com/security)). This is the provider's
control: the app relies on it but can't check or configure it.

The local stack (`docker compose` Postgres and the Supabase CLI) runs on the developer's own disk
and gets no provider encryption. It holds only seed and test data.

### At rest: app-level encryption

On top of the disk encryption, the API encrypts personal-data columns with Active Record
encryption, which uses AES-256-GCM. A column is encrypted before it leaves the API and decrypted
only inside it, so a database dump, a backup or a leaked database credential shows ciphertext for
these fields:

| Model | Encrypted columns | What they hold |
| --- | --- | --- |
| `Onboarding` | `full_name`, `date_of_birth`, `address` | The identity details the user confirmed |
| `DocumentUpload` | `draft_fields` | What OCR read from the ID, before the user confirms it |
| `Message` | `content` | Chat messages and assistant replies |
| `Conversation` | `assessment_draft` | Assessment answers collected so far |
| `Assessment` | `data` | The saved assessment |

The declarations are the `encrypts` lines in each model under `api/app/models/`. Encryption is
non-deterministic, so the same value encrypts differently each time and can't be matched across
rows.

The ID images themselves aren't encrypted by the app. They sit in the private bucket under the
provider's disk encryption, and are deleted on confirmation or within 2 hours (see
[privacy.md](privacy.md)).

### Keys

The keys come from environment variables, set in Railway in production and generated at random
by `bin/setup` for local use. Their values are never committed or logged.

| Variable | Use |
| --- | --- |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | Encrypts and decrypts the columns above |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | Required by Active Record encryption; no column uses deterministic encryption |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | Salt for deriving the encryption keys |
| `AUDIT_HMAC_KEY` | Not an encryption key: keys the HMAC that turns user IDs into pseudonymous audit references |
| `SUPABASE_SERVICE_ROLE_KEY` | Server-only key for Storage and the Auth admin API; never sent to the browser |

They are read in `api/config/application.rb` and `api/app/models/audit_event.rb`. Losing the
primary key makes the encrypted columns unreadable, so production keys need a backup outside
Railway. The app has no key rotation procedure yet.

## Access control

- **The user comes from the token.** The API verifies the Supabase sign-in token against the
  project's public keys (`Auth::JwtVerifier`) and takes the user from its `sub` claim, never from
  an ID in the request. Every query for an onboarding record, upload, conversation or booking is
  scoped to that user.
- **The browser never reads the database.** It uses Supabase only to sign in; all data goes
  through the API.
- **Row-level security is on, with no policies.** RLS is enabled on every table in the `public`
  schema, Rails' own tables included (`api/lib/boot/row_level_security.rb`). With no policy for
  the `anon` or `authenticated` roles, a leaked anon key reads nothing.
- **Admins are audited.** Admin endpoints (slot management) check the `admin` role in the token's
  `app_metadata`, which users can't edit, and each admin access writes an audit entry holding a
  pseudonymous actor reference.
