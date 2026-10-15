import {
  emptyResponse,
  errorEnvelope,
  hangingFetch,
  headerOf,
  htmlResponse,
  installFetch,
  jsonResponse,
} from '@/test-utils/fetch'
import { ApiError, createApiClient, DEFAULT_TIMEOUT_MS } from './client'

const BASE_URL = 'https://api.example.test'
const TOKEN = 'access-token-abc'

function makeClient(
  getAccessToken = async (): Promise<string | null> => TOKEN,
) {
  return createApiClient({ baseUrl: BASE_URL, getAccessToken })
}

async function rejectionOf(promise: Promise<unknown>): Promise<ApiError> {
  try {
    await promise
  } catch (error) {
    expect(error).toBeInstanceOf(ApiError)
    return error as ApiError
  }
  throw new Error('expected the request to reject')
}

describe('API client', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    fetchMock = installFetch()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  describe('sends the access token as a bearer token (R19)', () => {
    it('sets Authorization: Bearer <token> on every request', async () => {
      fetchMock.mockResolvedValue(jsonResponse(200, { ok: true }))

      await makeClient().request('/onboarding')

      const [url, init] = fetchMock.mock.calls[0]
      expect(url).toBe(`${BASE_URL}/onboarding`)
      expect(headerOf(init, 'Authorization')).toBe(`Bearer ${TOKEN}`)
    })

    it('asks for a fresh token on each request', async () => {
      fetchMock.mockResolvedValue(jsonResponse(200, {}))
      const getAccessToken = jest
        .fn<Promise<string | null>, []>()
        .mockResolvedValueOnce('first-token')
        .mockResolvedValueOnce('refreshed-token')
      const client = makeClient(getAccessToken)

      await client.request('/onboarding')
      await client.request('/onboarding')

      expect(headerOf(fetchMock.mock.calls[1][1], 'Authorization')).toBe(
        'Bearer refreshed-token',
      )
    })

    it('rejects with an unauthenticated error and sends nothing when signed out', async () => {
      const error = await rejectionOf(
        makeClient(async () => null).request('/onboarding'),
      )

      expect(error.code).toBe('unauthenticated')
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it('sends no user ID header, only the bearer token', async () => {
      fetchMock.mockResolvedValue(jsonResponse(200, {}))

      await makeClient().request('/bookings', {
        method: 'POST',
        body: { slot_id: 7 },
      })

      const [url, init] = fetchMock.mock.calls[0]
      expect(url).not.toMatch(/user/i)
      expect(headerOf(init, 'X-User-Id')).toBeNull()
      expect(String(init.body)).not.toMatch(/user/i)
    })
  })

  describe('request and response handling', () => {
    it('sends a JSON body with the method and content type', async () => {
      fetchMock.mockResolvedValue(jsonResponse(201, { id: 1 }))

      await makeClient().request('/bookings', {
        method: 'POST',
        body: { slot_id: 7 },
      })

      const [, init] = fetchMock.mock.calls[0]
      expect(init.method).toBe('POST')
      expect(headerOf(init, 'Content-Type')).toBe('application/json')
      expect(JSON.parse(init.body)).toEqual({ slot_id: 7 })
    })

    it('sends FormData untouched so the browser sets the multipart boundary', async () => {
      fetchMock.mockResolvedValue(jsonResponse(201, {}))
      const form = new FormData()
      form.append('image', new Blob(['x'], { type: 'image/jpeg' }))

      await makeClient().request('/documents', { method: 'POST', body: form })

      const [, init] = fetchMock.mock.calls[0]
      expect(init.body).toBe(form)
      expect(headerOf(init, 'Content-Type')).toBeNull()
    })

    it('defaults to GET with no body', async () => {
      fetchMock.mockResolvedValue(jsonResponse(200, {}))

      await makeClient().request('/slots')

      const [, init] = fetchMock.mock.calls[0]
      expect(init.method ?? 'GET').toBe('GET')
      expect(init.body ?? null).toBeNull()
    })

    it('resolves with the parsed JSON body on success', async () => {
      fetchMock.mockResolvedValue(
        jsonResponse(200, {
          slots: [{ id: 1, starts_at: '2026-11-02T15:00:00Z' }],
        }),
      )

      const body = await makeClient().request('/slots')

      expect(body).toEqual({
        slots: [{ id: 1, starts_at: '2026-11-02T15:00:00Z' }],
      })
    })

    it('resolves with undefined for 204 No Content', async () => {
      fetchMock.mockResolvedValue(emptyResponse(204))

      await expect(
        makeClient().request('/bookings/1', { method: 'DELETE' }),
      ).resolves.toBeUndefined()
    })
  })

  describe('parses the error envelope into user actions (R16, R30)', () => {
    it('exposes the code, message, status and actions from the envelope', async () => {
      fetchMock.mockResolvedValue(
        errorEnvelope(
          503,
          'llm_unavailable',
          'The assistant is unavailable right now.',
          ['retry', 'manual_entry'],
        ),
      )

      const error = await rejectionOf(makeClient().request('/chat/messages'))

      expect(error.status).toBe(503)
      expect(error.code).toBe('llm_unavailable')
      expect(error.message).toBe('The assistant is unavailable right now.')
      expect(error.actions).toEqual(['retry', 'manual_entry'])
    })

    it('passes through a 4xx envelope with no actions', async () => {
      fetchMock.mockResolvedValue(
        errorEnvelope(409, 'slot_taken', 'That slot was just taken.', []),
      )

      const error = await rejectionOf(makeClient().request('/bookings'))

      expect(error.status).toBe(409)
      expect(error.code).toBe('slot_taken')
      expect(error.actions).toEqual([])
    })

    it('drops actions it does not know how to show', async () => {
      fetchMock.mockResolvedValue(
        errorEnvelope(503, 'storage_unavailable', 'Storage is down.', [
          'retry',
          'call_support',
        ]),
      )

      const error = await rejectionOf(makeClient().request('/documents'))

      expect(error.actions).toEqual(['retry'])
    })

    it('turns a 5xx without an envelope into a clear retryable error, not raw HTML', async () => {
      fetchMock.mockResolvedValue(
        htmlResponse(502, '<html><body>Bad Gateway</body></html>'),
      )

      const error = await rejectionOf(makeClient().request('/slots'))

      expect(error.status).toBe(502)
      expect(error.code).toBe('unavailable')
      expect(error.actions).toEqual(['retry'])
      expect(error.message).not.toMatch(/<html|Bad Gateway/)
      expect(error.message.length).toBeGreaterThan(0)
    })
  })

  describe('a network failure or a hung API shows a retry within 10 s (R30)', () => {
    it('turns a network failure into a clear retryable error', async () => {
      fetchMock.mockRejectedValue(new TypeError('Failed to fetch'))

      const error = await rejectionOf(makeClient().request('/slots'))

      expect(error.code).toBe('network_error')
      expect(error.status).toBeNull()
      expect(error.actions).toEqual(['retry'])
      expect(error.message).not.toMatch(/Failed to fetch/)
      expect(error.message.length).toBeGreaterThan(0)
    })

    it('times out a hung request by the default timeout', async () => {
      jest.useFakeTimers()
      fetchMock.mockImplementation(hangingFetch)

      const pending = rejectionOf(makeClient().request('/slots'))
      await jest.advanceTimersByTimeAsync(DEFAULT_TIMEOUT_MS)
      const error = await pending

      expect(error.code).toBe('timeout')
      expect(error.status).toBeNull()
      expect(error.actions).toEqual(['retry'])
    })

    it('uses a default timeout under 10 s that still outlasts the 6 s server-side LLM timeout', () => {
      // The API answers a slow LLM with its own 503 envelope after 6 s; the
      // client must wait for that, yet give up before the 10 s budget.
      expect(DEFAULT_TIMEOUT_MS).toBeGreaterThan(6_000)
      expect(DEFAULT_TIMEOUT_MS).toBeLessThan(10_000)
    })

    it('honors a custom timeout', async () => {
      jest.useFakeTimers()
      fetchMock.mockImplementation(hangingFetch)
      const client = createApiClient({
        baseUrl: BASE_URL,
        getAccessToken: async () => TOKEN,
        timeoutMs: 1_000,
      })

      const pending = rejectionOf(client.request('/slots'))
      await jest.advanceTimersByTimeAsync(1_000)

      expect((await pending).code).toBe('timeout')
    })

    it('does not time out a request that answers in time', async () => {
      jest.useFakeTimers()
      fetchMock.mockResolvedValue(jsonResponse(200, { ok: true }))

      const body = await makeClient().request('/slots')
      await jest.advanceTimersByTimeAsync(DEFAULT_TIMEOUT_MS)

      expect(body).toEqual({ ok: true })
    })
  })
})
