import type { ApiClient } from '@/api/client'
import type { Assessment } from '@/chat/chatApi'
import { STEPS } from '@/shell/steps'

// The 200 body of GET /onboarding. Identity is a status only; its values
// never come back from the API after confirmation (R17).
export interface OnboardingStatus {
  step: string
  assessment: Assessment | null
  identity: {
    confirmed: boolean
    source: 'ocr' | 'manual' | null
    confirmed_at: string | null
  }
}

export async function fetchOnboarding(api: ApiClient) {
  return (await api.request<{ onboarding: OnboardingStatus }>('/onboarding'))
    .onboarding
}

// The page for a step the API reports. A step this app doesn't know starts at
// the chat rather than failing.
export function pathForStep(step: string) {
  return (STEPS.find(({ id }) => id === step) ?? STEPS[0]).path
}

export async function currentStepPath(api: ApiClient) {
  return pathForStep((await fetchOnboarding(api)).step)
}
