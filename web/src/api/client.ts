// The one way pages talk to the Rails API. It sends the Supabase access token
// as a bearer token (never a user ID, R19), gives up before the 10 s budget
// (R30) and turns every failure into an ApiError carrying the envelope's
// user actions (R16).

// Over the API's own 6 s LLM timeout, so its 503 envelope can still arrive,
// and under the 10 s the user may wait for a retry (R30).
export const DEFAULT_TIMEOUT_MS = 8_000

const KNOWN_ACTIONS = ['retry', 'manual_entry'] as const

export type ApiAction = (typeof KNOWN_ACTIONS)[number]

export interface ApiErrorInit {
  status: number | null
  code: string
  message: string
  actions: ApiAction[]
}

export class ApiError extends Error {
  readonly status: number | null
  readonly code: string
  readonly actions: ApiAction[]

  constructor({ status, code, message, actions }: ApiErrorInit) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
    this.actions = actions
  }
}

export interface ApiClientOptions {
  baseUrl: string
  getAccessToken: () => Promise<string | null>
  timeoutMs?: number
}

export interface RequestOptions {
  method?: string
  body?: FormData | object
}

export interface ApiClient {
  request<T = unknown>(path: string, options?: RequestOptions): Promise<T>
}

const UNAUTHENTICATED = new ApiError({
  status: 401,
  code: 'unauthenticated',
  message: 'Your session has ended. Please sign in again.',
  actions: [],
})

function clientError(code: string, message: string) {
  return new ApiError({ status: null, code, message, actions: ['retry'] })
}

function isKnownAction(action: unknown): action is ApiAction {
  return KNOWN_ACTIONS.includes(action as ApiAction)
}

function isJson(response: Response) {
  return (response.headers.get('content-type') ?? '').includes(
    'application/json',
  )
}

async function envelopeOf(response: Response) {
  if (!isJson(response)) return null
  try {
    const body: unknown = await response.json()
    const error = (body as { error?: unknown } | null)?.error
    if (typeof error !== 'object' || error === null) return null
    const { code, message, actions } = error as Record<string, unknown>
    if (typeof code !== 'string' || typeof message !== 'string') return null
    return {
      code,
      message,
      actions: Array.isArray(actions) ? actions.filter(isKnownAction) : [],
    }
  } catch {
    return null
  }
}

async function errorFrom(response: Response) {
  const envelope = await envelopeOf(response)
  if (envelope) return new ApiError({ status: response.status, ...envelope })
  if (response.status >= 500) {
    return new ApiError({
      status: response.status,
      code: 'unavailable',
      message: 'The service is unavailable right now. Please try again.',
      actions: ['retry'],
    })
  }
  return new ApiError({
    status: response.status,
    code: 'request_failed',
    message: 'Something went wrong with that request.',
    actions: [],
  })
}

function buildInit(
  token: string,
  { method = 'GET', body }: RequestOptions,
  signal: AbortSignal,
): RequestInit {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    Authorization: `Bearer ${token}`,
  }
  if (body === undefined) return { method, headers, signal }
  // FormData goes untouched so the browser sets the multipart boundary.
  if (body instanceof FormData) return { method, headers, body, signal }
  headers['Content-Type'] = 'application/json'
  return { method, headers, body: JSON.stringify(body), signal }
}

export function createApiClient({
  baseUrl,
  getAccessToken,
  timeoutMs = DEFAULT_TIMEOUT_MS,
}: ApiClientOptions): ApiClient {
  async function request<T>(path: string, options: RequestOptions = {}) {
    // Asked on every request so a refreshed token is always used.
    const token = await getAccessToken()
    if (!token) throw UNAUTHENTICATED

    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    try {
      const response = await fetch(
        `${baseUrl}${path}`,
        buildInit(token, options, controller.signal),
      )
      if (!response.ok) throw await errorFrom(response)
      if (response.status === 204 || !isJson(response)) return undefined as T
      return (await response.json()) as T
    } catch (error) {
      if (error instanceof ApiError) throw error
      if (controller.signal.aborted) {
        throw clientError(
          'timeout',
          'This is taking longer than it should. Please try again.',
        )
      }
      throw clientError(
        'network_error',
        'We could not reach the server. Check your connection and try again.',
      )
    } finally {
      clearTimeout(timer)
    }
  }

  return { request }
}
