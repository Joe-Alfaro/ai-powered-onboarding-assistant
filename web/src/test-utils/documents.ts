// Fakes for the identity pages, in the shapes the documents API returns (see
// "Documents and consent contracts set by the tests" in docs/decisions.md).
import { createApiClient } from '@/api/client'
import { errorEnvelope, jsonResponse, type FakeResponse } from './fetch'

export const API_BASE = 'https://api.example.test'

export function testApiClient() {
  return createApiClient({
    baseUrl: API_BASE,
    getAccessToken: async () => 'session-jwt',
  })
}

export type FieldName = 'full_name' | 'date_of_birth' | 'address'

export interface FieldReading {
  value: string
  confidence: number
  level: 'high' | 'low'
}

export type DocumentFields = Record<FieldName, FieldReading | null>

export interface DocumentBody {
  id: string
  status: 'pending'
  manual_entry: boolean
  reason: string
  fields: DocumentFields
}

export const NO_FIELDS: DocumentFields = {
  full_name: null,
  date_of_birth: null,
  address: null,
}

export const CLEAN_FIELDS: DocumentFields = {
  full_name: { value: 'Jane Q Sample', confidence: 93.5, level: 'high' },
  date_of_birth: { value: '1985-03-14', confidence: 91, level: 'high' },
  address: {
    value: '123 Fake St, Springfield, ZZ 00000',
    confidence: 91.4,
    level: 'high',
  },
}

// Name read well, address read poorly, date of birth not read at all.
export const PARTIAL_FIELDS: DocumentFields = {
  full_name: { value: 'Jane Q Sample', confidence: 95, level: 'high' },
  date_of_birth: null,
  address: { value: '123 Fake St', confidence: 42.3, level: 'low' },
}

export function documentBody(
  overrides: Partial<DocumentBody> = {},
): DocumentBody {
  return {
    id: 'doc-7f2c',
    status: 'pending',
    manual_entry: false,
    reason: 'ok',
    fields: CLEAN_FIELDS,
    ...overrides,
  }
}

export function documentResponse(overrides: Partial<DocumentBody> = {}) {
  return jsonResponse(200, { document: documentBody(overrides) })
}

export function manualEntryResponse(reason: string) {
  return documentResponse({ manual_entry: true, reason, fields: NO_FIELDS })
}

export function consentResponse(textVersion: string) {
  return jsonResponse(201, {
    consent: { text_version: textVersion, granted_at: '2026-10-15T14:00:00Z' },
  })
}

export function onboardingResponse(
  identity: Record<FieldName, string>,
  identitySource: 'ocr' | 'manual',
) {
  return jsonResponse(200, {
    onboarding: { ...identity, identity_source: identitySource },
  })
}

type Responder = (init: RequestInit | undefined) => FakeResponse

// Answers fetch by "METHOD /path" (the path after API_BASE). A request with no
// route gets a 404 envelope, so a test sees it in requestsMade() and fails on
// its own assertions rather than on a thrown error swallowed by the client.
export function routeFetch(
  fetchMock: jest.Mock,
  routes: Record<string, FakeResponse | Responder>,
) {
  fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
    const route = routes[`${init?.method ?? 'GET'} ${pathOf(url)}`]
    if (route === undefined) {
      return errorEnvelope(404, 'not_found', 'No such route in this test.', [])
    }
    return typeof route === 'function' ? route(init) : route
  })
}

function pathOf(url: string) {
  return url.startsWith(API_BASE) ? url.slice(API_BASE.length) : url
}

// Every request the page made, as "METHOD /path".
export function requestsMade(fetchMock: jest.Mock) {
  return fetchMock.mock.calls.map(
    ([url, init]: [string, RequestInit | undefined]) =>
      `${init?.method ?? 'GET'} ${pathOf(url)}`,
  )
}

// The parsed JSON body of the first request to "METHOD /path".
export function jsonBodyOf(fetchMock: jest.Mock, request: string) {
  const call = fetchMock.mock.calls.find(
    ([url, init]: [string, RequestInit | undefined]) =>
      `${init?.method ?? 'GET'} ${pathOf(url)}` === request,
  )
  if (!call) throw new Error(`No ${request} was made`)
  return JSON.parse(String(call[1].body)) as Record<string, unknown>
}

export function photoOfId(name = 'id.jpg', type = 'image/jpeg') {
  return new File([new Uint8Array([0xff, 0xd8, 0xff, 0xe0])], name, { type })
}

// A file that reports the given size without allocating it.
export function fileOfSize(bytes: number, name = 'big.jpg') {
  const file = photoOfId(name)
  Object.defineProperty(file, 'size', { value: bytes })
  return file
}

export const MB = 1024 * 1024
