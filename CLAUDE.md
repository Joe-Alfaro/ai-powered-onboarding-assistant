# Project instructions

## Workflow

- Follow the delivery loop: requirements live in `docs/requirements/onboarding-assistant.md`
  (refer to them by ID, such as R29), and every non-obvious choice goes in `docs/decisions.md`.
  The decisions log is append-only; to reverse a decision, add an entry naming the one it replaces.
- `ARCHITECTURE.md` is the approved design.

## Git and merging

- Merge requests go to the self-hosted GitLab remote, named `gitlab`. `origin` is a GitHub mirror;
  open no pull requests there. Never write the GitLab host name into any file, commit or MR text;
  call it "the GitLab remote" or `<gitlab host>`.
- One feature branch per change, off `main`. `main` is protected: changes reach it only through a
  merge request, and the MR pipeline must pass before merge.
- Run `npm install` at the root once to enable the Husky pre-push hook.

## GitLab server safety

The GitLab server is self-hosted and runaway loops have taken it down before. These rules are
mandatory.

- Never poll GitLab in a tight loop. Check pipeline or MR status at most once every 2 minutes.
- Never stream job logs (no `glab ci view --live`, no `glab ci trace` in a loop). Fetch at most the
  last 200 lines of a failed job's log, once.
- One push per real fix, never in a loop. If a pipeline fails twice for the same reason, stop and
  report instead of retrying. Never retry pipelines automatically. Never script loops of API calls,
  pushes or MR creation.
- `.gitlab-ci.yml` runs pipelines only on `merge_request_event`: no branch or `main` pipelines, no
  schedules, triggers or child pipelines. Every job has `interruptible: true`, `retry: 0` and
  `timeout: 30m`. No `artifacts:` and no remote cache. Keep to one `gates` job, and keep logs
  small: quiet flags, no verbose reporters, never print files or environment variables.
- CI runs on a shared shell-executor runner on the user's Mac, with no `services:` containers. The
  job uses the host toolchain and starts its own Postgres container on a dedicated port, removing it
  when the job ends.
- Never touch `~/.gitlab-runner/config.toml`.
- Merge your own MR only when the orchestrator says to.

## Never commit

- `_private/` and `.env` (or any `.env.*` except `.env.example`). Never print `.env` values.
- Company or program names, anywhere: code, comments, test data, docs, commits or branch names.

## Gates

`bin/gates` runs every gate; the pre-push hook and the CI `gates` job both call it.

- `api/`: `bundle exec rubocop`, `bundle exec rspec` (needs Postgres: `docker compose up -d postgres`).
- `web/`: `npm run lint`, `npm run format:check`, `npm run typecheck`, `npm run test:coverage`.
- Secret scan: `gitleaks git --redact .` over the full history.
