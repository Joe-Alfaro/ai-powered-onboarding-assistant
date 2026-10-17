import { expect, signIn, test, type FakeLlmMode } from './support/fixtures'

// R16 and R30: when the LLM provider fails, the user gets "try again" and
// "continue manually" within 10 s, with no hang and no made-up commitment.
const FAILURES: { mode: FakeLlmMode; name: string }[] = [
  { mode: 'timeout', name: 'times out' },
  { mode: 'server-error', name: 'returns a 5xx' },
  { mode: 'rate-limit', name: 'returns a 429' },
]

test.describe('R16: LLM failure degrades gracefully', () => {
  FAILURES.forEach(({ mode, name }) => {
    test(`when the provider ${name}, the chat offers try again and continue manually within 10 s`, async ({
      page,
      user,
      fakeLlm,
    }) => {
      await signIn(page, user)
      await expect(page).toHaveURL(/\/chat$/)
      await fakeLlm.setMode(mode)

      await page
        .getByLabel('Message')
        .fill('I would like help with settling in.')
      const sent = Date.now()
      await page.getByRole('button', { name: 'Send' }).click()

      const alert = page.getByRole('main').getByRole('alert')
      await expect(
        alert.getByRole('button', { name: 'Try again' }),
      ).toBeVisible({
        timeout: 10_000,
      })
      await expect(
        alert.getByRole('button', { name: 'Enter details manually' }),
      ).toBeVisible()
      expect(Date.now() - sent).toBeLessThan(10_000)
      await expect(
        page.getByRole('log', { name: 'Conversation' }),
      ).not.toContainText(/booked|confirmed|appointment is/i)

      await fakeLlm.setMode('normal')
      await alert.getByRole('button', { name: 'Try again' }).click()
      await expect(
        page.getByRole('log', { name: 'Conversation' }).getByText('Assistant:'),
      ).toBeVisible()
    })
  })

  test('continue manually leads to the manual entry form', async ({
    page,
    user,
    fakeLlm,
  }) => {
    await signIn(page, user)
    await fakeLlm.setMode('server-error')
    await page.getByLabel('Message').fill('I would like help with settling in.')
    await page.getByRole('button', { name: 'Send' }).click()

    await page.getByRole('button', { name: 'Enter details manually' }).click()
    await expect(page).toHaveURL(/\/identity\/manual$/)
    await expect(page.getByLabel('Full name')).toBeVisible()
  })
})
