// k6 load test for the chatbot and the API (R22, R38). 20 virtual users for 60 s against
// BASE_URL; each user is one load-test user (bin/rake perf:users) and loops over the health
// check, the main reads, a chat message and a booking that it cancels again.
//
//   k6 run -e BASE_URL=https://api.example.test -e LLM_MODE=real perf/load.js
//
// Environment:
//   BASE_URL      the API, no trailing slash (required)
//   LLM_MODE      what the chat path hits, recorded in the output (required):
//                 real (a real provider), fake (the local fake LLM, see perf/local-api.sh)
//                 or off (no chat requests)
//   TOKENS_FILE   JSON array of access tokens (default ../api/tmp/perf-tokens.json)
//   SUMMARY_FILE  also write the summary as JSON to this path
//   VUS, DURATION override 20 and 60s, for a quick smoke run
//
// Expected statuses: 2xx everywhere, plus 409 on POST /bookings (another user took the slot
// first). Anything else counts as an error. HTTP 429s from any endpoint and LLM rate limits
// (a chat 503 with code llm_rate_limited, after the fallback provider) are counted separately.
import http from "k6/http";
import { check, sleep } from "k6";
import { Counter, Rate } from "k6/metrics";

const BASE_URL = (__ENV.BASE_URL || "").replace(/\/$/, "");
const LLM_MODE = __ENV.LLM_MODE || "";
const VUS = Number(__ENV.VUS || 20);
const DURATION = __ENV.DURATION || "60s";
const TOKENS = JSON.parse(
  open(__ENV.TOKENS_FILE || "../api/tmp/perf-tokens.json"),
);
const ENDPOINTS = ["health", "slots", "onboarding", "chat", "book", "cancel"];
const CHAT_MESSAGES = [
  "I would like help with stress at work, weekday mornings suit me.",
  "What happens on the first call?",
  "Can I book a time next week?",
];

if (!BASE_URL)
  throw new Error(
    "Set BASE_URL to the API, for example -e BASE_URL=http://localhost:3001",
  );
if (!["real", "fake", "off"].includes(LLM_MODE)) {
  throw new Error(
    "Set LLM_MODE to real, fake or off, so the output records what the chat path hit",
  );
}
if (!Array.isArray(TOKENS) || TOKENS.length === 0)
  throw new Error("TOKENS_FILE has no tokens");

const errors = new Rate("errors");
const http429 = new Counter("http_429");
const llmRateLimited = new Counter("llm_rate_limited");

const thresholds = { http_req_duration: ["p(95)<3000"], errors: ["rate<0.01"] };
for (const name of ENDPOINTS) {
  if (name === "chat" && LLM_MODE === "off") continue;
  thresholds[`http_req_duration{name:${name}}`] = ["p(95)<3000"];
}

export const options = {
  scenarios: {
    load: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds,
  summaryTrendStats: ["avg", "med", "p(95)", "max"],
};

// A 409 on booking means another user won the slot: an expected outcome, not a failed request.
const bookingStatuses = http.expectedStatuses({ min: 200, max: 299 }, 409);

function headers() {
  const token = TOKENS[(__VU - 1) % TOKENS.length];
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

function record(response, name, ok) {
  if (response.status === 429) http429.add(1, { name });
  errors.add(!ok, { name });
  check(response, { [`${name} ok`]: () => ok });
}

function request(method, path, name, body, params = {}) {
  return http.request(
    method,
    `${BASE_URL}${path}`,
    body ? JSON.stringify(body) : null,
    {
      headers: headers(),
      tags: { name },
      ...params,
    },
  );
}

function json(response) {
  try {
    return response.json();
  } catch {
    return {};
  }
}

function book(slots) {
  if (slots.length === 0) return;
  const slot = slots[Math.floor(Math.random() * slots.length)];
  const booked = request(
    "POST",
    "/bookings",
    "book",
    { slot_id: slot.id },
    { responseCallback: bookingStatuses },
  );
  const code = json(booked).error?.code;
  record(
    booked,
    "book",
    booked.status === 201 || code === "slot_taken" || code === "booking_exists",
  );

  // Cancel what this user holds, so the next iteration can book again.
  let bookingId = json(booked).booking?.id;
  if (!bookingId && code === "booking_exists") {
    bookingId = json(request("GET", "/bookings", "bookings")).bookings?.[0]?.id;
  }
  if (bookingId) {
    const cancelled = request("DELETE", `/bookings/${bookingId}`, "cancel");
    record(cancelled, "cancel", cancelled.status === 200);
  }
}

export default function () {
  const health = http.get(`${BASE_URL}/health`, { tags: { name: "health" } });
  record(health, "health", health.status === 200);

  const slots = request("GET", "/slots", "slots");
  record(slots, "slots", slots.status === 200);

  const onboarding = request("GET", "/onboarding", "onboarding");
  record(onboarding, "onboarding", onboarding.status === 200);

  if (LLM_MODE !== "off") {
    const message = CHAT_MESSAGES[__ITER % CHAT_MESSAGES.length];
    const chat = request("POST", "/chat/messages", "chat", { message });
    if (json(chat).error?.code === "llm_rate_limited") llmRateLimited.add(1);
    record(chat, "chat", chat.status === 200);
  }

  book(json(slots).slots || []);
  sleep(1);
}

function metric(data, name) {
  return data.metrics[name]?.values || {};
}

function ms(value) {
  return value === undefined ? "n/a" : `${Math.round(value)} ms`;
}

export function handleSummary(data) {
  const overall = metric(data, "http_req_duration");
  const result = {
    base_url: BASE_URL,
    llm_mode: LLM_MODE,
    vus: VUS,
    duration: DURATION,
    requests: metric(data, "http_reqs").count || 0,
    p95_ms: overall["p(95)"],
    error_rate: metric(data, "errors").rate || 0,
    http_429: metric(data, "http_429").count || 0,
    llm_rate_limited: metric(data, "llm_rate_limited").count || 0,
    endpoints: {},
    finished_at: new Date().toISOString(),
  };
  for (const name of ENDPOINTS) {
    const values = metric(data, `http_req_duration{name:${name}}`);
    if (values["p(95)"] !== undefined)
      result.endpoints[name] = {
        p95_ms: values["p(95)"],
        median_ms: values.med,
      };
  }

  const lines = [
    `k6 load: ${result.vus} VUs for ${result.duration} against ${BASE_URL}`,
    `LLM on the chat path: ${LLM_MODE}`,
    `requests: ${result.requests}, p95: ${ms(result.p95_ms)}, error rate: ${(result.error_rate * 100).toFixed(2)}%`,
    `HTTP 429 responses: ${result.http_429}, LLM rate-limited chat replies: ${result.llm_rate_limited}`,
    ...Object.entries(result.endpoints).map(
      ([name, values]) =>
        `  ${name.padEnd(10)} p95 ${ms(values.p95_ms)}, median ${ms(values.median_ms)}`,
    ),
  ];
  const output = { stdout: `${lines.join("\n")}\n` };
  if (__ENV.SUMMARY_FILE)
    output[__ENV.SUMMARY_FILE] = JSON.stringify(result, null, 2);
  return output;
}
