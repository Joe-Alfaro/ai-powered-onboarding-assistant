# Deploying

Production is one hosted Supabase project (one Postgres database, Auth and Storage) and two
Railway services built from this repository: `api` (root `api/`) and `web` (root `web/`). Both
build from their Dockerfiles, configured by `api/railway.toml` and `web/railway.toml`, and deploy
with the Railway CLI.

Follow the steps in order. No value below is a real secret: wherever a step says `<...>`, use the
value from the Supabase dashboard or one you generate, and set it only in Railway. Never commit
one.

## 1. Supabase project

1. Create a project. Note the project ref (`<ref>`), and keep the database password you set.
2. **JWT signing keys (asymmetric).** Project Settings → JWT Keys. Create a standby key of type
   ECC (P-256, `ES256`), then rotate to it so it becomes the current key. The API verifies sign-in
   tokens against the JWKS endpoint, which only publishes asymmetric keys. Check it:

   ```sh
   curl -s https://<ref>.supabase.co/auth/v1/.well-known/jwks.json
   ```

   The answer must list a key with `"alg":"ES256"`. Don't revoke the previous (legacy) JWT
   secret: the legacy anon and service role keys in step 3 are signed with it.
3. **API keys.** Project Settings → API Keys → Legacy API keys. Copy the `anon` key (for the web
   service) and the `service_role` key (for the API service only; it bypasses all access rules).
4. **Auth URLs.** Authentication → URL Configuration. Set these after step 2.3 below, once the web
   domain exists:
   - Site URL: `https://<web domain>`
   - Redirect URLs: `https://<web domain>/**`
5. **Auth provider.** Authentication → Sign In / Providers: Email enabled, with password sign-in.
6. **Database role.** SQL Editor, run once (generate a strong password; it goes only into
   `DATABASE_URL`):

   ```sql
   create role onboarding_api with login password '<generated password>';
   grant usage, create on schema public to onboarding_api;
   ```

   The API connects as this role and owns every table it creates, so row-level security (R19)
   denies the anon and authenticated roles while the API itself is unrestricted.
7. **Connection string: use the session pooler.** Connect → Session pooler (port 5432 on the
   pooler host, for example `aws-0-<region>.pooler.supabase.com`). Railway reaches Supabase over
   IPv4, and the direct database host is IPv6 only. Replace the user with `onboarding_api.<ref>`
   and the password with the role's, and add `sslmode=require`:

   ```
   postgresql://onboarding_api.<ref>:<role password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require
   ```

   Don't use the transaction pooler (port 6543). The app has prepared statements off, so queries
   would work, but migrations take an advisory lock that needs a session.
8. **Storage bucket.** Nothing to do: every API boot runs `bin/rails storage:ensure_bucket`, which
   creates `STORAGE_BUCKET` as a **private** bucket if it's missing and leaves it alone if it
   exists. After the first deploy, check Storage in the dashboard shows the bucket as private.

## 2. Railway services

Install the Railway CLI and sign in (`railway login`). From the repository root:

1. Create the project: `railway init` (name it, for example, `onboarding-assistant`).
2. Create the two empty services: `railway add --service api` and `railway add --service web`.
3. Generate a public domain for each:

   ```sh
   railway domain --service api
   railway domain --service web
   ```

   Note both (`<api domain>`, `<web domain>`), then finish Supabase step 1.4.

### API service variables

Set each with `railway variables --service api --set "NAME=value"`. `PORT` is set by Railway;
Puma listens on it. See `api/.env.example` for what each one does.

| Variable | Value |
| --- | --- |
| `RAILS_ENV` | `production` (the image sets it too; `railway run` needs it) |
| `SECRET_KEY_BASE` | a random value: `bin/rails secret` |
| `DATABASE_URL` | the session pooler string from Supabase step 1.7 |
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_JWKS_URL` | `https://<ref>.supabase.co/auth/v1/.well-known/jwks.json` |
| `SUPABASE_SERVICE_ROLE_KEY` | the `service_role` key |
| `STORAGE_BUCKET` | `id-documents` |
| `WEB_ORIGIN` | `https://<web domain>` (CORS; the API won't boot without it) |
| `SOLID_QUEUE_IN_PUMA` | `true` (runs jobs, including the hourly upload purge, in the web process) |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`, `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | from `bin/rails db:encryption:init` (run locally; copy the three values, never commit them) |
| `AUDIT_HMAC_KEY` | a random value: `bin/rails secret` |
| `LLM_PROVIDER`, `LLM_MODEL` | the chosen provider and model |
| `LLM_FALLBACK_PROVIDER`, `LLM_FALLBACK_MODEL` | optional fallback |
| `GROQ_API_KEY`, `CLAUDE_API_KEY`, `GEMINI_API_KEY` | only the keys for the configured providers |
| `MAX_UPLOAD_MB`, `OCR_CONFIDENCE_THRESHOLD`, `RAILS_MAX_THREADS`, `RAILS_LOG_LEVEL` | optional; defaults in `api/.env.example` |

`RAILS_MASTER_KEY` isn't needed: `SECRET_KEY_BASE` replaces the credentials file.

### Web service variables

`next build` copies `NEXT_PUBLIC_` values into the browser bundle, so they must be set **before**
the build; `web/Dockerfile` takes them as build arguments. Changing one needs a new deploy. None
of them is a secret.

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://<ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | the `anon` key |
| `NEXT_PUBLIC_API_URL` | `https://<api domain>` |
| `NEXT_PUBLIC_LONG_PAUSE_SECONDS` | `45` |
| `NEXT_PUBLIC_MAX_UPLOAD_MB` | the same as the API's `MAX_UPLOAD_MB` (`10`) |

## 3. Deploy

From the repository root, upload each service with its own folder as the root, so Railway finds
that folder's `railway.toml` and `Dockerfile`:

```sh
railway up api --path-as-root --service api
railway up web --path-as-root --service web
```

The API image's entrypoint runs `bin/rails db:prepare` (on the first deploy this loads the whole
schema: app tables, Solid Queue and Solid Cache), then `bin/rails storage:ensure_bucket`, then
starts Puma. Railway marks the deploy healthy when `GET /health` answers 200, and restarts the
service on failure.

## 4. Seed the demo data

Run once after the first deploy, and again whenever you want fresh slots. It's idempotent: it
adds open slots on the next 14 days' weekdays at fixed UTC hours, creates the two demo users
through the Supabase Auth admin API (confirmed, so they can sign in at once) and leaves existing
slots and users alone. It doesn't create the load-test users (`rake perf:users` does, on request).

```sh
cd api
railway run --service api bin/rails db:seed
```

`railway run` runs the command on your machine with the API service's variables, so it needs the
API's Ruby and gems installed locally (`bundle install`). It connects to Supabase through the same
session pooler string. It prints the demo credentials.

## 5. Verify

1. `curl -s https://<api domain>/health` answers 200 with `"status"` not `"down"`, and each
   dependency (database, storage, OCR, LLM) listed.
2. In Supabase Storage, the bucket `id-documents` exists and is private.
3. In Supabase Table Editor, the `solid_queue_recurring_tasks` table lists
   `purge_expired_document_uploads` once the API has been up for a minute.
4. Open `https://<web domain>`, sign in with a demo user from the seed output, and book a slot.
5. Check the logs (`railway logs --service api`) show single-line JSON and no errors.

## Checking a build locally

Before a deploy, you can build and boot both images with placeholder values:

```sh
docker build -t onboarding-api api
docker build -t onboarding-web \
  --build-arg NEXT_PUBLIC_SUPABASE_URL=https://placeholder.supabase.co \
  --build-arg NEXT_PUBLIC_SUPABASE_ANON_KEY=placeholder \
  --build-arg NEXT_PUBLIC_API_URL=http://localhost:3001 \
  --build-arg NEXT_PUBLIC_LONG_PAUSE_SECONDS=45 \
  --build-arg NEXT_PUBLIC_MAX_UPLOAD_MB=10 web
docker run --rm -e PORT=8080 -p 8080:8080 onboarding-web
```

`api/spec/deploy/production_database_spec.rb` runs the production `db:prepare` and seed against
an empty local Postgres on every gates run.
