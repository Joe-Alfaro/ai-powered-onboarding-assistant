import { API_URL } from './support/stack'
import { arriveAtSchedule, expect, signIn, test } from './support/fixtures'

// R30: neither the Rails API nor Next.js shows a default error page, and a
// dependency that is down gives a clear message and a retry within 10 s.
const NEXT_DEFAULT_404 = /This page could not be found/
const NEXT_DEFAULT_ERROR =
  /Application error: a client-side exception has occurred/

test.describe('R30: no default error pages', () => {
  test("an unknown web page shows the app's own not-found page", async ({
    page,
  }) => {
    const response = await page.goto('/no-such-page')

    expect(response?.status()).toBe(404)
    await expect(
      page.getByRole('heading', { name: 'Page not found' }),
    ).toBeVisible()
    await expect(
      page.getByRole('link', { name: 'Back to the start' }),
    ).toBeVisible()
    await expect(page.locator('body')).not.toContainText(NEXT_DEFAULT_404)
  })

  test('an unknown API route answers with the JSON error envelope, not a Rails page', async ({
    request,
  }) => {
    const response = await request.get(`${API_URL}/no-such-route`)

    expect(response.status()).toBe(404)
    expect(response.headers()['content-type']).toContain('application/json')
    const body = (await response.json()) as {
      error?: { code?: string; message?: string }
    }
    expect(body.error?.code).toBeTruthy()
    expect(body.error?.message).toBeTruthy()
  })

  test('with the API unreachable, a step shows a clear message and a retry within 10 s', async ({
    page,
    user,
  }) => {
    await arriveAtSchedule(user)
    await signIn(page, user)
    await expect(page).toHaveURL(/\/schedule$/)

    await page.route(`${API_URL}/**`, (route) =>
      route.abort('connectionrefused'),
    )
    await page.reload()

    const alert = page.getByRole('main').getByRole('alert')
    await expect(alert.getByRole('button', { name: 'Try again' })).toBeVisible({
      timeout: 10_000,
    })
    await expect(alert).not.toBeEmpty()
    await expect(page.locator('body')).not.toContainText(NEXT_DEFAULT_ERROR)

    await page.unroute(`${API_URL}/**`)
    await alert.getByRole('button', { name: 'Try again' }).click()
    await expect(
      page.getByRole('group', { name: 'Available times' }),
    ).toBeVisible()
  })

  test("an API failure that returns an HTML 500 still shows the app's message and a retry", async ({
    page,
    user,
  }) => {
    await arriveAtSchedule(user)
    await signIn(page, user)
    await expect(page).toHaveURL(/\/schedule$/)

    // The CORS preflight goes through; the GET gets an HTML 500, as from a
    // proxy in front of a crashed API.
    await page.route(`${API_URL}/slots`, (route) =>
      route.request().method() === 'OPTIONS'
        ? route.continue()
        : route.fulfill({
            status: 500,
            contentType: 'text/html',
            headers: { 'access-control-allow-origin': '*' },
            body: '<h1>oops</h1>',
          }),
    )
    await page.reload()

    const alert = page.getByRole('main').getByRole('alert')
    await expect(alert).toContainText('The service is unavailable right now')
    await expect(alert.getByRole('button', { name: 'Try again' })).toBeVisible()
    await expect(page.locator('body')).not.toContainText(NEXT_DEFAULT_ERROR)
  })
})
