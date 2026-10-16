import type { Page } from '@playwright/test'
import {
  ASSESSMENT_MESSAGES,
  GOLDEN_IMAGE,
  SYNTHETIC,
  continueControl,
  expect,
  inSequence,
  tabTo,
  test,
} from './support/fixtures'

// R34: the whole flow with the keyboard alone. Every control is reached with
// Tab and used with Enter, Space or typing; the mouse is never used.

async function typeInto(page: Page, label: string, text: string) {
  await tabTo(page, page.getByLabel(label, { exact: true }))
  await page.keyboard.press('ControlOrMeta+A')
  await page.keyboard.type(text)
}

async function pressButton(page: Page, name: string) {
  await tabTo(page, page.getByRole('button', { name, exact: true }))
  await page.keyboard.press('Enter')
}

test('R34: every step, including the chat, file picker and slot picker, works with the keyboard alone', async ({
  page,
  user,
}) => {
  await test.step('sign in', async () => {
    await page.goto('/sign-in')
    await typeInto(page, 'Email', user.email)
    await typeInto(page, 'Password', user.password)
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/chat$/)
  })

  await test.step('chat to a complete assessment', async () => {
    const turns = page
      .getByRole('log', { name: 'Conversation' })
      .getByRole('listitem')
    await inSequence(ASSESSMENT_MESSAGES, async (message) => {
      const before = await turns.count()
      await typeInto(page, 'Message', message)
      await page.keyboard.press('Enter')
      await expect(turns).toHaveCount(before + 2)
    })
    await expect(page.getByText('Assessment complete')).toBeVisible()
    await tabTo(page, continueControl(page))
    await page.keyboard.press('Enter')
    await expect(page).toHaveURL(/\/identity$/)
  })

  await test.step('consent and pick the file with the keyboard', async () => {
    await tabTo(page, page.getByRole('checkbox', { name: /I agree/ }))
    await page.keyboard.press('Space')
    await pressButton(page, 'Continue')

    await tabTo(page, page.getByLabel('Photo of your ID'))
    const chooser = page.waitForEvent('filechooser')
    await page.keyboard.press('Space')
    await (await chooser).setFiles(GOLDEN_IMAGE)
    await pressButton(page, 'Upload photo')
    await expect(page).toHaveURL(/\/confirm\?document=/, { timeout: 30_000 })
  })

  await test.step('confirm edited fields', async () => {
    await typeInto(page, 'Full name', SYNTHETIC.fullName)
    await typeInto(page, 'Date of birth', SYNTHETIC.dateOfBirth)
    await typeInto(page, 'Address', SYNTHETIC.address)
    await pressButton(page, 'Confirm details')
    await expect(page).toHaveURL(/\/schedule$/)
  })

  await test.step('pick a slot with the arrow keys and book it', async () => {
    const radios = page
      .getByRole('group', { name: 'Available times' })
      .getByRole('radio')
    await tabTo(page, radios.first())
    await page.keyboard.press('ArrowDown')
    await expect(radios.nth(1)).toBeChecked()
    await pressButton(page, 'Book this time')
    await expect(
      page.getByRole('status').filter({ hasText: 'Your call is booked.' }),
    ).toBeVisible()
    await tabTo(page, continueControl(page))
    await page.keyboard.press('Enter')
  })

  await test.step('reach the done page', async () => {
    await expect(page).toHaveURL(/\/done$/)
    await expect(
      page.getByRole('heading', { name: "You're all set" }),
    ).toBeVisible()
  })
})
