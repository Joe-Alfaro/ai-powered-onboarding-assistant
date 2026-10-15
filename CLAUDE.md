# Project instructions

## Workflow

- Follow the delivery loop: requirements live in `docs/requirements/onboarding-assistant.md`
  (refer to them by ID, such as R29), and every non-obvious choice goes in `docs/decisions.md`.
  The decisions log is append-only; to reverse a decision, add an entry naming the one it replaces.
- `ARCHITECTURE.md` is the approved design.

## Git and merging

- The repository is on GitLab. One feature branch per change, off `main`.
- Changes reach `main` only through a Merge Request on GitLab, and CI (`.gitlab-ci.yml`) must pass
  before it merges.
- Run `npm install` at the root once to enable the Husky pre-push hook.

## Never commit

- `_private/` and `.env` (or any `.env.*` except `.env.example`). Never print `.env` values.
- Company or program names, anywhere: code, comments, test data, docs, commits or branch names.

## Gates

- `api/`: `bundle exec rubocop`, `bundle exec rspec` (needs Postgres: `docker compose up -d postgres`).
- `web/`: `npm run lint`, `npm run format:check`, `npm run typecheck`, `npm run test:coverage`.
