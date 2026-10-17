#!/bin/sh
# Starts the Rails API for the end-to-end tests on a fresh api_e2e database:
# drops and reloads the schema, runs the real seed (open slots and the demo
# users in the local Supabase Auth), then serves. The environment comes from
# playwright.config.ts; nothing here reads api/.env values that it sets.
set -eu

cd "$(dirname "$0")/../../../api"

# Truthy to Puma when set at all, even empty, so make sure they are unset.
unset SOLID_QUEUE_IN_PUMA PIDFILE

export DISABLE_DATABASE_ENVIRONMENT_CHECK=1
bin/rails db:drop db:create db:schema:load > /dev/null
bin/rails db:seed > /dev/null

exec bin/rails server -b 127.0.0.1 -p "$PORT" -P tmp/pids/e2e-server.pid
