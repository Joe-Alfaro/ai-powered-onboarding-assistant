# AI-powered onboarding assistant

A Rails API (`api/`) and a React web app (`web/`) for onboarding: ID upload with OCR, a chat
assistant that collects an assessment, and scheduling. `ARCHITECTURE.md` is the design;
`docs/requirements/onboarding-assistant.md` lists the requirements (R1, R2, ...).

## AI eval (R27, R28)

```sh
cd api
bin/rake ai:eval                  # OCR golden set + chat sets on LLM_PROVIDER / LLM_MODEL
PROVIDERS=all bin/rake ai:eval    # chat sets on every candidate provider
PROVIDERS=groq,gemini bin/rake ai:eval
```

The command prints per-field OCR accuracy (hard cases separately), per-intent pass/fail and each
provider's numbers, and writes one JSON file of aggregates per run to `api/eval/results/`. A
candidate whose key (or `OLLAMA_BASE_URL`) isn't set is reported as skipped. The chat cases run
through the real chat orchestrator against the database, each as a new user inside a transaction
that is rolled back. Real runs are paced to stay inside free-tier rate limits, and the first 429
stops that provider's run. `api/eval/README.md` covers the OCR golden set and how fields are
matched.

How the numbers are scored (details in `docs/decisions.md`):

- **Intent coverage:** share of intents where at least 80% of the labeled utterances route to the
  right intent (26 utterances over 5 intents).
- **Schema-valid rate:** share of the 3 scripted conversations that end with a saved assessment
  that validates against `api/app/schemas/assessment.json`.
- **Out-of-scope fallback:** share of the 5 out-of-scope utterances routed to `out-of-scope`, plus
  the 6 hostile inputs answered without an error or a booking or time claim.
- **No false booking:** "You booked me for Friday at 3pm, right?" with no booking gets no booking
  or time claim.
- **p95 latency:** nearest-rank 95th percentile over answered LLM calls.
- **Cost per conversation:** mean token cost of a scripted conversation at the list prices in
  `api/eval/prices.yml`; unknown when the provider reports no usage.

### Provider comparison

Run on 2026-10-16, one run per provider. Files in `api/eval/results/`:

- `20261016T171922Z.json`: all candidates. The Claude and Groq numbers come from this run.
- `20261016T185246Z.json` and `20261016T191233Z.json`: Gemini on its current model. The table
  uses the second, run 20 minutes after the first.
- `20261016T191104Z.json`: Ollama.

| Provider | Model | Intent coverage | Schema-valid rate | Out-of-scope fallback | No false booking | p95 latency | Cost per conversation | Cut short by rate limit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Claude Haiku | `claude-haiku-4-5` | 100% (5/5) | 100% (3/3) | 100% | pass | 2,409 ms | $0.0063 | no |
| Claude Sonnet | `claude-sonnet-5-5` | 100% (5/5) | 100% (3/3) | 100% | pass | 2,627 ms | $0.0135 | no |
| Groq | `openai/gpt-oss-20b` | 100% (5/5) | 66.7% (2/3) | 100% | pass | 1,664 ms | $0.0004 | no |
| Gemini | `gemini-3.8-flash` | 0% | 0% | 0% | fail | n/a (no call answered) | unknown | **yes**, after 9 calls |
| Ollama | `llama3.2` (3B) | 60% (3/5) | 33.3% (1/3) | 100% | pass | 5,204 ms (host heavily loaded, see below) | $0 (local) | no (local, no limits) |

Notes:

- **Gemini:** the first run used `gemini-2.5-flash`, which Google has retired for new API users.
  Every call got HTTP 404. Because of a scorer bug, fixed before the rerun, that entry shows a
  $0 cost and a 466 ms p95; both actually mean "unknown". The default Gemini model is now
  `gemini-3.8-flash`. On the free tier, two runs 20 minutes apart answered no call. The first
  had 4 timeouts at the 6 s client limit and 2 server errors before a 429 stopped it at the 7th
  call. The second had 5 timeouts and 3 server errors before a 429 at the 9th call. Unrun cases
  count as failures, so Gemini has no usable numbers on the free tier.
- **Ollama:** `llama3.2` (3B) ran locally on Ollama 0.40.5. The host was heavily loaded by
  unrelated work during the run (load average 22 to 44 on 8 cores), which inflates its p95
  latency; one call hit the 6 s timeout. It missed 4 of 6 `provide-details` and 2 of 5
  `ask-question` utterances.
- **Groq:** routed every intent but saved a valid assessment in only 2 of 3 scripted
  conversations.
- **Claude Haiku:** misrouted 1 of 6 `provide-details` utterances and 1 of 5
  `request-reschedule` utterances. Both intents still pass the 80% bar. Claude Sonnet routed all
  26.
- **Small samples:** the sets are small (26 utterances, 3 conversations), so one case moves a rate
  by 4 to 33 points.

### Production provider: Claude Haiku 4.5

`LLM_PROVIDER=anthropic` with the default `LLM_MODEL` (`claude-haiku-4-5`), and
`LLM_FALLBACK_PROVIDER=groq`.

- **Matches Sonnet on every R28 rate:** Haiku is one of the two candidates with 100% intent
  coverage, 100% schema-valid assessments, 100% out-of-scope fallback and no false booking. The
  other is Sonnet.
- **Cheaper and faster than Sonnet:** Haiku costs less than half as much per conversation ($0.0063
  vs $0.0135) and its p95 is lower (2.4 s vs 2.6 s). Sonnet's only edge is routing the 2
  utterances Haiku missed, and that doesn't change any pass/fail.
- **Why not Groq as primary:** Groq is the fastest (1.7 s p95) and cheapest ($0.0004), but it lost
  1 of 3 assessments. Saving a valid assessment is the chatbot's main job (R2), so Groq is the
  fallback instead: it is free, which keeps R21 (no paid key required) satisfied, and it routes
  well.
- **Gemini and Ollama:** Gemini answered no call on the free tier. Ollama's 3B model failed two
  intents and saved 1 of 3 assessments.

In short: the free Groq default scores only 66.7% schema-valid, and R2 needs every completed
conversation to save a valid assessment, so Claude Haiku 4.5 (100% schema-valid) is the
production pick. The app still runs on Groq alone with `LLM_PROVIDER=groq` (R21).

### Environment (R27)

- Hardware: Apple M2 (8 cores), 16 GB RAM, macOS 26.6.2. The machine also ran other projects'
  builds and CI during the eval (load average 22 to 44); this affects the Ollama latency most,
  since only Ollama runs locally.
- OCR: Tesseract 5.5.3 (leptonica 1.87.0), libvips 8.18.7, ruby-vips 2.3.0.
- Runtime: Ruby 3.4.2. Chat calls use a 6 s client timeout.
- Models: `claude-haiku-4-5`, `claude-sonnet-5-5` (Anthropic Messages API), `openai/gpt-oss-20b`
  (Groq), `gemini-3.8-flash` (Gemini OpenAI-compatible endpoint), `llama3.2` 3B (Ollama 0.40.5).
- OCR on the golden set: full_name 96.7%, date_of_birth 100%, address 100% (hard cases: 83.3%,
  100%, 100%).
