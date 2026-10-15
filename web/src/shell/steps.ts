// The onboarding flow in order. The step nav and the route group layout both
// read this, so a new step is added here once.
export const STEPS = [
  { id: 'chat', label: 'Chat', path: '/chat' },
  { id: 'identity', label: 'Your ID', path: '/identity' },
  { id: 'confirm', label: 'Confirm details', path: '/confirm' },
  { id: 'schedule', label: 'Schedule a call', path: '/schedule' },
  { id: 'done', label: 'Done', path: '/done' },
] as const

export type StepId = (typeof STEPS)[number]['id']

// The step a route belongs to, counting nested routes such as
// /identity/manual, or null outside the flow.
export function stepFromPath(pathname: string): StepId | null {
  const step = STEPS.find(
    ({ path }) => pathname === path || pathname.startsWith(`${path}/`),
  )
  return step?.id ?? null
}
