import { ApiError, type ApiAction, type ApiClient } from '@/api/client'

export interface Assessment {
  reason: string
  urgency: string
  preferred_window: string
  distress: boolean
  notes: string | null
}

// The 200 body of POST /chat/messages. Scheduling outcomes reach the user only
// through `reply`, which the API writes (R3).
export interface ChatMessageResponse {
  reply: string
  intent: string
  trigger: string | null
  actions: ApiAction[]
  assessment: Assessment | null
  scheduling: Record<string, unknown> | null
}

export function sendChatMessage(client: ApiClient, message: string) {
  return client.request<ChatMessageResponse>('/chat/messages', {
    method: 'POST',
    body: { message },
  })
}

// The client's own timeout and network errors carry only `retry`. The chat
// step also offers manual entry for them, so a hung or unreachable API is
// never a dead end (R16, R30).
const NOT_THE_USERS_DOING = ['timeout', 'network_error']

export function withManualEntry(error: ApiError) {
  if (
    !NOT_THE_USERS_DOING.includes(error.code) ||
    error.actions.includes('manual_entry')
  ) {
    return error
  }
  return new ApiError({
    status: error.status,
    code: error.code,
    message: error.message,
    actions: [...error.actions, 'manual_entry'],
  })
}
