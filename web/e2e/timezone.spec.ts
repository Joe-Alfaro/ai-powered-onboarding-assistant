import {
  arriveAtSchedule,
  expect,
  openSlots,
  signIn,
  test,
} from './support/fixtures'
import { bookFirstSlot } from './support/flow'

// R37: a browser far from UTC, at a half-hour offset, so a UTC or server-zone
// time can't pass by accident.
const ZONE = 'Asia/Kolkata'
test.use({ timezoneId: ZONE, locale: 'en-US' })

function clock(iso: string, timeZone: string) {
  return new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(iso))
}

test('R37: a user in a non-UTC timezone sees slots and the confirmation in local time, labeled with the zone', async ({
  page,
  user,
}) => {
  await arriveAtSchedule(user)
  const [earliest] = await openSlots(user)
  const local = clock(earliest.starts_at, ZONE)
  const utc = clock(earliest.starts_at, 'UTC')
  const zoneLabel = /GMT\+5:30|IST|India Standard Time/

  await signIn(page, user)
  const radio = page.locator(`input[type="radio"][value="${earliest.id}"]`)
  const label = page.locator(`label[for="${await radio.getAttribute('id')}"]`)
  await expect(label).toContainText(local)
  await expect(label).toContainText(zoneLabel)
  await expect(label).not.toContainText(utc)

  const booked = await bookFirstSlot(page)
  expect(booked).toContain(local)
  const booking = page.getByRole('region', { name: 'Your booking' })
  await expect(booking).toContainText(local)
  await expect(booking).toContainText(zoneLabel)

  await page.goto('/done')
  await expect(page.getByText(/Your call is on/)).toContainText(local)
  await expect(page.getByText(/Your call is on/)).toContainText(zoneLabel)
})
