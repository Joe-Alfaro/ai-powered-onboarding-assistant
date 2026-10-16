import {
  apiRequest,
  arriveAtSchedule,
  createUser,
  expect,
  openSlots,
  signIn,
  test,
} from './support/fixtures'

test('R7: booking a slot someone else just took shows a clear message, drops the slot and lets the user pick another', async ({
  page,
  user,
}) => {
  const other = await createUser()
  await Promise.all([arriveAtSchedule(user), arriveAtSchedule(other)])
  await signIn(page, user)
  await expect(page).toHaveURL(/\/schedule$/)

  const times = page.getByRole('group', { name: 'Available times' })
  const first = times.getByRole('radio').first()
  const takenId = await first.getAttribute('value')
  expect(takenId).toBeTruthy()
  const otherBooking = await apiRequest(other, '/bookings', {
    method: 'POST',
    body: { slot_id: takenId },
  })
  expect(otherBooking.status, 'the other user books it first').toBeLessThan(300)

  await first.check()
  await page.getByRole('button', { name: 'Book this time' }).click()

  await expect(page.getByRole('main').getByRole('alert')).toHaveText(
    'That time was just taken by someone else. Please pick another time.',
  )
  await expect(times.locator(`input[value="${takenId}"]`)).toHaveCount(0)
  expect((await openSlots(user)).map(({ id }) => id)).not.toContain(takenId)

  await times.getByRole('radio').first().check()
  await page.getByRole('button', { name: 'Book this time' }).click()
  await expect(
    page.getByRole('status').filter({ hasText: 'Your call is booked.' }),
  ).toBeVisible()
})
