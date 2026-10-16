import { FAKE_LLM_URL } from './support/stack'
import { SYNTHETIC, apiRequest, expect, test } from './support/fixtures'

// Guards against the other tests passing for the wrong reason: a console
// capture that sees nothing, or chat answered by anything but the fake LLM.
test.describe('e2e harness', () => {
  test('the browser console capture records what a page logs', async ({
    page,
    browserLog,
  }) => {
    await page.goto('/sign-in')
    await page.evaluate((value) => console.info(value), SYNTHETIC.fullName)

    await expect.poll(() => browserLog.join('\n')).toContain(SYNTHETIC.fullName)
  })

  test('chat messages are answered by the fake LLM, never a real provider', async ({
    user,
  }) => {
    async function calls() {
      const response = await fetch(`${FAKE_LLM_URL}/__calls`)
      return ((await response.json()) as { calls: number }).calls
    }
    const before = await calls()

    const { status } = await apiRequest(user, '/chat/messages', {
      method: 'POST',
      body: { message: 'I would like help with settling in.' },
    })

    expect(status).toBe(200)
    expect(await calls()).toBe(before + 1)
  })
})
