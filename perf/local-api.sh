#!/bin/sh
# Starts the API for a local performance run (docs/performance.md), in the foreground. Its log
# also goes to api/log/perf-server.log, the LOG_FILE for bin/rake perf:ocr and perf:booking.
#
#   LLM_MODE=fake  also starts the fake LLM from the end-to-end tests and points the API at it
#                  through the Ollama adapter, with real provider keys blanked, so no key is used
#   LLM_MODE=real  uses the provider in api/.env (LLM_PROVIDER and its key)
#
# Everything else (database, Supabase, encryption keys) comes from api/.env or the environment.
# PORT defaults to 3001 and FAKE_LLM_PORT to 3413.
set -eu

cd "$(dirname "$0")/../api"
port="${PORT:-3001}"

case "${LLM_MODE:-}" in
  fake)
    fake_port="${FAKE_LLM_PORT:-3413}"
    node ../web/e2e/support/fake-llm.mjs "$fake_port" &
    fake_pid=$!
    trap 'kill "$fake_pid" 2> /dev/null' EXIT INT TERM
    export LLM_PROVIDER=ollama LLM_MODEL=fake OLLAMA_BASE_URL="http://127.0.0.1:$fake_port"
    # Blank, not unset, so a local api/.env can't supply them.
    for name in LLM_FALLBACK_PROVIDER CLAUDE_API_KEY GROQ_API_KEY GEMINI_API_KEY; do
      export "$name="
    done
    ;;
  real) ;;
  *)
    echo "Set LLM_MODE to fake or real" >&2
    exit 1
    ;;
esac

# Truthy to Puma when set at all, even empty.
unset SOLID_QUEUE_IN_PUMA PIDFILE

bin/rails server -b 127.0.0.1 -p "$port" -P tmp/pids/perf-server.pid 2>&1 | tee log/perf-server.log
