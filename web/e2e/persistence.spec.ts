import { arriveAtSchedule, expect, signIn, test } from './support/fixtures'
import { bookFirstSlot } from './support/flow'

test.describe('R8: bookings persist across sessions', () => {
  test('after signing out and back in, the user sees their booking', async ({
    page,
    user,
  }) => {
    await arriveAtSchedule(user)
    await signIn(page, user)
    const booked = await bookFirstSlot(page)

    await page.getByRole('button', { name: 'Sign out' }).click()
    await expect(page).toHaveURL(/\/sign-in$/)
    await page.goto('/schedule')
    await expect(page).toHaveURL(/\/sign-in$/)

    await signIn(page, user)
    await expect(page).toHaveURL(/\/done$/)
    await expect(page.getByText(`Your call is on ${booked}.`)).toBeVisible()
    await page.goto('/schedule')
    await expect(
      page.getByRole('region', { name: 'Your booking' }),
    ).toContainText(booked)
  })

  test('from a new browser, the user sees their booking', async ({
    page,
    user,
    browser,
  }) => {
    await arriveAtSchedule(user)
    await signIn(page, user)
    const booked = await bookFirstSlot(page)

    const fresh = await browser.newContext()
    const other = await fresh.newPage()
    await signIn(other, user)
    await expect(other).toHaveURL(/\/done$/)
    await expect(other.getByText(`Your call is on ${booked}.`)).toBeVisible()
    await fresh.close()
  })
})
