// A deterministic stand-in for an OpenAI-compatible LLM provider, so the
// end-to-end tests never call a real one. The API reaches it through its
// Ollama adapter (OLLAMA_BASE_URL), with no change to app code.
//
// POST /v1/chat/completions answers from simple keyword rules on the latest
// user message. POST /__control sets a failure mode for the next calls:
//   { "mode": "normal" | "server-error" | "rate-limit" | "timeout" }
// GET /__calls returns how many completions were requested.
import { createServer } from 'node:http'

const port = Number(process.argv[2] ?? 3412)
let mode = 'normal'
let calls = 0

const DISTRESS = /\b(overwhelmed|scared|panicking|anxious)\b/i
const URGENCY = /\b(urgent|urgently|as soon as possible)\b/i
const WINDOW = /\b(weekday|weekend)\s+(mornings|afternoons|evenings)\b/i
const REASON = /\bhelp with ([^,.]+)/i

function fieldsFrom(text) {
  const fields = {}
  const reason = text.match(REASON)
  if (reason) fields.reason = reason[1].trim()
  if (URGENCY.test(text)) fields.urgency = 'high'
  const window = text.match(WINDOW)
  if (window) fields.preferred_window = window[0].toLowerCase()
  return fields
}

function answer(text) {
  if (DISTRESS.test(text)) {
    return {
      intent: 'express-distress',
      assessment_fields: { distress: true },
      reply: 'That sounds hard. We can take this one step at a time.',
    }
  }
  const fields = fieldsFrom(text)
  if (Object.keys(fields).length === 0) {
    return {
      intent: 'out-of-scope',
      assessment_fields: {},
      reply: 'I can help you get started. What brings you here?',
    }
  }
  return {
    intent: 'provide-details',
    assessment_fields: fields,
    reply: 'Thank you, I have noted that.',
  }
}

function latestUserText(body) {
  const messages = Array.isArray(body?.messages) ? body.messages : []
  const user = messages.filter((message) => message.role === 'user').at(-1)
  return typeof user?.content === 'string' ? user.content : ''
}

function send(response, status, payload) {
  response.writeHead(status, { 'content-type': 'application/json' })
  response.end(JSON.stringify(payload))
}

function readJson(request) {
  return new Promise((resolve) => {
    let raw = ''
    request.on('data', (chunk) => {
      raw += chunk
    })
    request.on('end', () => {
      try {
        resolve(JSON.parse(raw || '{}'))
      } catch {
        resolve({})
      }
    })
  })
}

async function completion(request, response) {
  calls += 1
  const body = await readJson(request)
  if (mode === 'timeout') return // never answers; the API's client timeout fires
  if (mode === 'server-error') {
    return send(response, 500, { error: { message: 'fake outage' } })
  }
  if (mode === 'rate-limit') {
    return send(response, 429, { error: { message: 'fake rate limit' } })
  }
  send(response, 200, {
    id: `fake-${calls}`,
    object: 'chat.completion',
    model: body.model ?? 'fake',
    choices: [
      {
        index: 0,
        finish_reason: 'stop',
        message: {
          role: 'assistant',
          content: JSON.stringify(answer(latestUserText(body))),
        },
      },
    ],
  })
}

const server = createServer(async (request, response) => {
  const path = (request.url ?? '').split('?')[0]
  if (request.method === 'POST' && path.endsWith('/chat/completions')) {
    return completion(request, response)
  }
  if (request.method === 'POST' && path === '/__control') {
    const body = await readJson(request)
    mode = typeof body.mode === 'string' ? body.mode : 'normal'
    return send(response, 200, { mode })
  }
  if (request.method === 'GET' && path === '/__calls') {
    return send(response, 200, { calls })
  }
  if (request.method === 'GET' && path.endsWith('/models')) {
    return send(response, 200, { object: 'list', data: [{ id: 'fake' }] })
  }
  send(response, 404, { error: { message: 'not found' } })
})

server.listen(port, '127.0.0.1')
