import type { UserEvent } from '@testing-library/user-event'

// Presses Tab until the element has focus, the way a keyboard-only user
// reaches it. Fails instead of looping forever when it is unreachable.
export async function tabTo(user: UserEvent, element: Element, maxTabs = 25) {
  const reached = await Array.from({ length: maxTabs }).reduce<
    Promise<boolean>
  >(
    async (previous) => {
      if (await previous) return true
      await user.tab()
      return document.activeElement === element
    },
    Promise.resolve(document.activeElement === element),
  )
  if (!reached) {
    throw new Error(
      `Could not reach the element with Tab in ${maxTabs} presses`,
    )
  }
}
