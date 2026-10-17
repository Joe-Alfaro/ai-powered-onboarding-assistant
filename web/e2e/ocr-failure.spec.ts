import { TRIGGERS } from '../src/support/triggers'
import { API_URL } from './support/stack'
import {
  UNREADABLE_IMAGE,
  completeAssessment,
  expect,
  signIn,
  test,
} from './support/fixtures'
import {
  bookFirstSlot,
  continueToNextStep,
  enterIdentityManually,
  giveConsent,
  uploadId,
} from './support/flow'

test.describe('R10: OCR failure falls back to manual entry', () => {
  test('an image OCR cannot read offers manual entry for all fields, with no 500, and the user carries on to the schedule', async ({
    page,
    user,
  }) => {
    const serverErrors: string[] = []
    page.on('response', (response) => {
      if (response.url().startsWith(API_URL) && response.status() >= 500) {
        serverErrors.push(
          `${response.status()} ${new URL(response.url()).pathname}`,
        )
      }
    })
    await completeAssessment(user)
    await signIn(page, user)

    await giveConsent(page)
    await uploadId(page, UNREADABLE_IMAGE)

    await expect(page.getByRole('main').getByRole('alert')).toContainText(
      'We could not read your ID clearly enough',
      { timeout: 30_000 },
    )
    // R9: a failed or unreadable upload fires its own supportive content.
    await expect(
      page.getByRole('heading', {
        name: TRIGGERS['upload-failure'].content.heading,
      }),
    ).toBeVisible()

    await page
      .getByRole('button', { name: 'Skip and enter details manually' })
      .click()
    await expect(page.getByLabel('Full name')).toHaveValue('')
    await expect(page.getByLabel('Date of birth')).toHaveValue('')
    await expect(page.getByLabel('Address')).toHaveValue('')
    await enterIdentityManually(page)

    await expect(page).toHaveURL(/\/schedule$/)
    expect(serverErrors, 'API responses with a 5xx status').toEqual([])
  })

  test('a user can finish onboarding without uploading any image', async ({
    page,
    user,
  }) => {
    await completeAssessment(user)
    await signIn(page, user)
    await expect(page).toHaveURL(/\/identity$/)

    await page
      .getByRole('button', { name: 'Skip and enter details manually' })
      .click()
    await enterIdentityManually(page)
    const booked = await bookFirstSlot(page)
    await continueToNextStep(page)

    await expect(page).toHaveURL(/\/done$/)
    await expect(
      page.getByText('Confirmed from the details you entered.'),
    ).toBeVisible()
    await expect(page.getByText(`Your call is on ${booked}.`)).toBeVisible()
  })
})
