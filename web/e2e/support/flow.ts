import type { Page } from '@playwright/test'
import {
  ASSESSMENT_MESSAGES,
  SYNTHETIC,
  continueControl,
  expect,
  inSequence,
} from './fixtures'

// The happy path one step at a time, with the mouse and the page's labels.
// Each step ends on the next step's page.

export async function chatToCompleteAssessment(page: Page) {
  await expect(page).toHaveURL(/\/chat$/)
  const message = page.getByLabel('Message')
  await inSequence(ASSESSMENT_MESSAGES, async (text) => {
    const replies = page
      .getByRole('log', { name: 'Conversation' })
      .getByRole('listitem')
    const before = await replies.count()
    await message.fill(text)
    await page.getByRole('button', { name: 'Send' }).click()
    // The user's turn and the assistant's reply.
    await expect(replies).toHaveCount(before + 2)
  })
  await expect(page.getByText('Assessment complete')).toBeVisible()
  await expect(
    page.getByRole('region', { name: 'Assessment summary' }),
  ).toContainText(SYNTHETIC.reason)
}

export async function continueToNextStep(page: Page) {
  const next = continueControl(page)
  await expect(next, 'a Continue control to the next step').toBeVisible()
  await next.click()
}

export async function giveConsent(page: Page) {
  await expect(page).toHaveURL(/\/identity$/)
  const agree = page.getByRole('checkbox', { name: /I agree/ })
  // R12: the consent control isn't pre-selected.
  await expect(agree).not.toBeChecked()
  await agree.check()
  await page.getByRole('button', { name: 'Continue' }).click()
}

export async function uploadId(page: Page, file: string) {
  await page.getByLabel('Photo of your ID').setInputFiles(file)
  await page.getByRole('button', { name: 'Upload photo' }).click()
}

// Checks OCR pre-filled the name, then replaces every field, as a user
// correcting the read would.
export async function confirmEditedFields(page: Page, ocrName: RegExp) {
  await expect(page).toHaveURL(/\/confirm\?document=/, { timeout: 30_000 })
  const name = page.getByLabel('Full name')
  await expect(name).toHaveValue(ocrName)
  await name.fill(SYNTHETIC.fullName)
  await page.getByLabel('Date of birth').fill(SYNTHETIC.dateOfBirth)
  await page.getByLabel('Address').fill(SYNTHETIC.address)
  await page.getByRole('button', { name: 'Confirm details' }).click()
}

export async function enterIdentityManually(page: Page) {
  await expect(page).toHaveURL(/\/identity\/manual$/)
  await page.getByLabel('Full name').fill(SYNTHETIC.fullName)
  await page.getByLabel('Date of birth').fill(SYNTHETIC.dateOfBirth)
  await page.getByLabel('Address').fill(SYNTHETIC.address)
  await page.getByRole('button', { name: 'Save and continue' }).click()
}

// Books the earliest open time and returns its label as shown.
export async function bookFirstSlot(page: Page) {
  await expect(page).toHaveURL(/\/schedule$/)
  const times = page.getByRole('group', { name: 'Available times' })
  const first = times.getByRole('radio').first()
  const label = await page
    .locator(`label[for="${await first.getAttribute('id')}"]`)
    .innerText()
  await first.check()
  await page.getByRole('button', { name: 'Book this time' }).click()
  await expect(
    page.getByRole('status').filter({ hasText: 'Your call is booked.' }),
  ).toBeVisible()
  return label
}
