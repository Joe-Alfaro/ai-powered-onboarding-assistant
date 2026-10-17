import {
  GOLDEN_IMAGE,
  arriveAtSchedule,
  completeAssessment,
  expect,
  expectAccessible,
  signIn,
  test,
} from './support/fixtures'
import { bookFirstSlot, giveConsent, uploadId } from './support/flow'

// R34: axe (WCAG 2.1 A and AA, color contrast included) on every page, each
// in the state a user sees it. Failures are soft, so one run lists every page.
test.describe('R34: axe reports no serious or critical violations', () => {
  test('on the sign-in and not-found pages', async ({ page }) => {
    await page.goto('/sign-in')
    await expect(page.getByRole('button', { name: 'Sign in' })).toBeVisible()
    await expectAccessible(page, 'sign-in')

    await page.getByRole('button', { name: 'Sign in' }).click()
    await expectAccessible(page, 'sign-in with a validation error')

    await page.goto('/no-such-page')
    await expect(
      page.getByRole('heading', { name: 'Page not found' }),
    ).toBeVisible()
    await expectAccessible(page, 'not-found')
  })

  test('on the chat page, before and after a reply', async ({ page, user }) => {
    await signIn(page, user)
    await expect(page).toHaveURL(/\/chat$/)
    await expectAccessible(page, 'chat')

    await page.getByLabel('Message').fill('I would like help with settling in.')
    await page.getByRole('button', { name: 'Send' }).click()
    await expect(
      page.getByRole('log', { name: 'Conversation' }).getByRole('listitem'),
    ).toHaveCount(2)
    await expectAccessible(page, 'chat with a reply')
  })

  test('on the consent, upload, confirm and manual entry pages', async ({
    page,
    user,
  }) => {
    await completeAssessment(user)
    await signIn(page, user)
    await expect(page).toHaveURL(/\/identity$/)
    await expectAccessible(page, 'consent')

    await giveConsent(page)
    await expect(page.getByLabel('Photo of your ID')).toBeVisible()
    await expectAccessible(page, 'upload')

    await uploadId(page, GOLDEN_IMAGE)
    await expect(
      page.getByRole('button', { name: 'Confirm details' }),
    ).toBeVisible({
      timeout: 30_000,
    })
    await expectAccessible(page, 'confirm')

    await page.goto('/identity/manual')
    await expect(
      page.getByRole('button', { name: 'Save and continue' }),
    ).toBeVisible()
    await expectAccessible(page, 'manual entry')
  })

  test('on the schedule, done and privacy pages', async ({ page, user }) => {
    await arriveAtSchedule(user)
    await signIn(page, user)
    await expect(
      page.getByRole('group', { name: 'Available times' }),
    ).toBeVisible()
    await expectAccessible(page, 'schedule')

    await bookFirstSlot(page)
    await expectAccessible(page, 'schedule with a booking')

    await page.goto('/done')
    await expect(
      page.getByRole('heading', { name: "You're all set" }),
    ).toBeVisible()
    await expect(page.getByText(/Your call is on/)).toBeVisible()
    await expectAccessible(page, 'done')

    await page.goto('/privacy')
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    await expectAccessible(page, 'privacy')
  })
})
