// jsdom has no fetch, Response or Headers. These fakes stand in for fetch at
// the network boundary with just the parts a client reads: ok, status,
// headers.get, json() and text().

export interface FakeResponse {
  ok: boolean
  status: number
  headers: { get(name: string): string | null }
  json(): Promise<unknown>
  text(): Promise<string>
}

function fakeResponse(
  status: number,
  contentType: string | null,
  bodyText: string,
): FakeResponse {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: {
      get: (name) =>
        name.toLowerCase() === 'content-type' ? contentType : null,
    },
    json: async () => JSON.parse(bodyText),
    text: async () => bodyText,
  }
}

export function jsonResponse(status: number, body: unknown) {
  return fakeResponse(status, 'application/json', JSON.stringify(body))
}

export function htmlResponse(status: number, html: string) {
  return fakeResponse(status, 'text/html', html)
}

export function emptyResponse(status = 204) {
  return fakeResponse(status, null, '')
}

export function errorEnvelope(
  status: number,
  code: string,
  message: string,
  actions: string[],
) {
  return jsonResponse(status, { error: { code, message, actions } })
}

// A fetch that never answers until its AbortSignal fires, like a server that
// accepted the connection and then hung.
export function hangingFetch(_url: string, init?: RequestInit) {
  return new Promise<FakeResponse>((_resolve, reject) => {
    init?.signal?.addEventListener('abort', () => {
      reject(new DOMException('The operation was aborted.', 'AbortError'))
    })
  })
}

export function installFetch() {
  const fetchMock = jest.fn()
  Object.defineProperty(globalThis, 'fetch', {
    configurable: true,
    writable: true,
    value: fetchMock,
  })
  return fetchMock
}

// Reads a request header whether the client passed a plain object, an array
// of pairs or a Headers-like object.
export function headerOf(
  init: RequestInit | undefined,
  name: string,
): string | null {
  const headers = init?.headers
  if (!headers) return null
  if (typeof (headers as Headers).get === 'function') {
    return (headers as Headers).get(name)
  }
  const pairs = Array.isArray(headers)
    ? headers
    : Object.entries(headers as Record<string, string>)
  const match = pairs.find(([key]) => key.toLowerCase() === name.toLowerCase())
  return match ? match[1] : null
}
