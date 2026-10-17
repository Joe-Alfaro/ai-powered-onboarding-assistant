import { ApiError, type ApiAction, type ApiClient } from '@/api/client'

export interface Assessment {
  reason: string
  urgency: string
  preferred_window: string
  distress: boolean
  notes: string | null
}

// Times are ISO-8601 UTC; the page shows them in the browser's zone (R37).
export interface SlotSummary {
  id: string
  starts_at: string
  ends_at: string
}

// What the user can pick in reply to a reschedule or cancel request (R36).
export type ChatChoice =
  | { type: 'slot'; booking_id: string; slot: SlotSummary }
  | { type: 'confirm_cancel'; booking_id: string }

// Scheduling::Booker's result. `slot` on a failed outcome is the slot asked
// for, not one the user holds.
export interface SchedulingResult {
  outcome: string
  booking_id: string | null
  slot: SlotSummary | null
  previous_slot: SlotSummary | null
}

// The 200 body of POST /chat/messages. The reply text never states a time
// (R3); the new time comes from `scheduling`.
export interface ChatMessageResponse {
  reply: string
  intent: string
  trigger: string | null
  actions: ApiAction[]
  assessment: Assessment | null
  scheduling: SchedulingResult | null
  // Optional so a reply from an older API still renders.
  choices?: ChatChoice[]
}

// A chosen choice as the API reads it back.
export type ChoiceParams =
  { booking_id: string; slot_id: string } | { booking_id: string; cancel: true }

export function choiceParams(choice: ChatChoice): ChoiceParams {
  return choice.type === 'slot'
    ? { booking_id: choice.booking_id, slot_id: choice.slot.id }
    : { booking_id: choice.booking_id, cancel: true }
}

export function sendChatMessage(
  client: ApiClient,
  message: string,
  choice?: ChoiceParams,
) {
  return client.request<ChatMessageResponse>('/chat/messages', {
    method: 'POST',
    body: { message, ...choice },
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
