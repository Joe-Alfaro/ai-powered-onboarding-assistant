import { TRIGGERS } from '../src/support/triggers'
import { LONG_PAUSE_SECONDS } from './support/stack'
import { expect, signIn, test } from './support/fixtures'

// R9: the long-pause trigger, with the threshold set short through
// NEXT_PUBLIC_LONG_PAUSE_SECONDS in the e2e build.
const heading = TRIGGERS['long-pause'].content.heading
const thresholdMs = LONG_PAUSE_SECONDS * 1_000

test.describe('R9: long-pause supportive content', () => {
  test.setTimeout(thresholdMs * 3 + 30_000)

  test('appears after the configured inactivity threshold on an onboarding step, and not before', async ({
    page,
    user,
  }) => {
    await signIn(page, user)
    await expect(page).toHaveURL(/\/chat$/)
    const idleSince = Date.now()

    await page.waitForTimeout(thresholdMs / 2)
    await expect(page.getByRole('heading', { name: heading })).toHaveCount(0)

    await expect(page.getByRole('heading', { name: heading })).toBeVisible({
      timeout: thresholdMs,
    })
    expect(Date.now() - idleSince).toBeGreaterThanOrEqual(thresholdMs - 500)
  })

  test('does not fire while the user is typing', async ({ page, user }) => {
    await signIn(page, user)
    await expect(page).toHaveURL(/\/chat$/)
    const message = page.getByLabel('Message')
    await message.focus()

    // A key every quarter of the threshold, for one and a half thresholds.
    const keys = 'still typing'.split('').slice(0, 6)
    await keys.reduce(
      (previous, key) =>
        previous.then(async () => {
          await page.keyboard.type(key)
          await page.waitForTimeout(thresholdMs / 4)
        }),
      Promise.resolve(),
    )
    await expect(page.getByRole('heading', { name: heading })).toHaveCount(0)
  })
})
