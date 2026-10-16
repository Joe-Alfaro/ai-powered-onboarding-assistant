import {
  GOLDEN_IMAGE,
  GOLDEN_NAME,
  SYNTHETIC,
  expect,
  expectNoSupportiveContent,
  signIn,
  test,
} from './support/fixtures'
import {
  bookFirstSlot,
  chatToCompleteAssessment,
  confirmEditedFields,
  continueToNextStep,
  giveConsent,
  uploadId,
} from './support/flow'

// One walk through the flow carries three done checks, so the shared host runs
// the slowest path once.
test('full happy path: sign in, chat to a complete assessment, consent, upload, confirm edits, book, done; no supportive content (R9) and no synthetic values in the browser console (R15)', async ({
  page,
  user,
  browserLog,
}) => {
  await test.step('sign in and chat to a complete assessment', async () => {
    await signIn(page, user)
    await chatToCompleteAssessment(page)
    await expectNoSupportiveContent(page)
    await continueToNextStep(page)
  })

  await test.step('consent, unticked by default, then upload a golden-set image', async () => {
    await giveConsent(page)
    await expectNoSupportiveContent(page)
    await uploadId(page, GOLDEN_IMAGE)
  })

  await test.step('confirm the OCR fields after editing them', async () => {
    await confirmEditedFields(page, GOLDEN_NAME)
    await expect(page).toHaveURL(/\/schedule$/)
    await expectNoSupportiveContent(page)
  })

  const booked = await test.step('book a slot', async () => {
    const label = await bookFirstSlot(page)
    await expect(
      page.getByRole('region', { name: 'Your booking' }),
    ).toContainText(label)
    await expectNoSupportiveContent(page)
    await continueToNextStep(page)
    return label
  })

  await test.step('the done page sums up the assessment, identity and booking', async () => {
    await expect(page).toHaveURL(/\/done$/)
    await expect(
      page.getByRole('heading', { name: "You're all set" }),
    ).toBeVisible()
    await expect(
      page.getByRole('region', { name: 'Assessment summary' }),
    ).toContainText(SYNTHETIC.reason)
    await expect(page.getByText('Confirmed from your ID photo.')).toBeVisible()
    await expect(page.getByText(`Your call is on ${booked}.`)).toBeVisible()
    await expectNoSupportiveContent(page)
  })

  await test.step('R15: none of the synthetic values reached the browser console', async () => {
    const leaks = [
      SYNTHETIC.fullName,
      'Marbleworth',
      SYNTHETIC.dateOfBirth,
      'Lanternfish',
      'Zanzibarbaroque',
      'Templeton',
      user.email,
    ].filter((value) => browserLog.some((line) => line.includes(value)))
    expect(leaks, 'synthetic values found in the browser console').toEqual([])
  })
})
