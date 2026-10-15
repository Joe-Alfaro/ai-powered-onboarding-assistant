import { formatLocalDateTime } from './formatLocalDateTime'

// Slot times arrive from the API as UTC ISO strings and must be shown in the
// browser's own zone. jest.config.mjs runs every test with
// TZ=America/New_York, standing in for a browser outside UTC; the timeZone
// option lets the tests check other zones too.
const BROWSER_ZONE = 'America/New_York'

describe('formatLocalDateTime (R37)', () => {
  it('runs these tests in a browser zone that is not UTC', () => {
    expect(Intl.DateTimeFormat().resolvedOptions().timeZone).toBe(BROWSER_ZONE)
  })

  describe('a user in a different timezone sees local time labeled with the zone', () => {
    it("uses the browser's zone by default, not UTC", () => {
      const text = formatLocalDateTime('2026-11-02T15:00:00Z', {
        locale: 'en-US',
      })

      expect(text).toMatch(/10:00/)
      expect(text).toMatch(/EST/)
      expect(text).not.toMatch(/3:00/)
      expect(text).toBe(
        formatLocalDateTime('2026-11-02T15:00:00Z', {
          locale: 'en-US',
          timeZone: BROWSER_ZONE,
        }),
      )
    })

    it('uses the daylight-saving label when the slot falls in summer time', () => {
      const text = formatLocalDateTime('2026-07-01T15:00:00Z', {
        locale: 'en-US',
      })

      expect(text).toMatch(/11:00/)
      expect(text).toMatch(/EDT/)
    })

    it('shows a half-hour offset zone correctly, including a date change', () => {
      const text = formatLocalDateTime('2026-11-02T20:00:00Z', {
        locale: 'en-US',
        timeZone: 'Asia/Kolkata',
      })

      expect(text).toMatch(/Nov 3/)
      expect(text).toMatch(/1:30/)
      expect(text).toMatch(/GMT\+5:30/)
    })

    it('includes the calendar date, not just the time', () => {
      const text = formatLocalDateTime('2026-11-03T02:00:00Z', {
        locale: 'en-US',
        timeZone: 'America/Los_Angeles',
      })

      // 02:00 UTC on Nov 3 is still Nov 2 in Los Angeles.
      expect(text).toMatch(/Nov 2/)
      expect(text).toMatch(/6:00/)
      expect(text).toMatch(/PST/)
    })

    it('renders the same instant differently in two zones', () => {
      const iso = '2026-11-02T15:00:00Z'

      const berlin = formatLocalDateTime(iso, {
        locale: 'en-US',
        timeZone: 'Europe/Berlin',
      })
      const sydney = formatLocalDateTime(iso, {
        locale: 'en-US',
        timeZone: 'Australia/Sydney',
      })

      expect(berlin).not.toEqual(sydney)
    })

    it('accepts an explicit offset other than Z', () => {
      const text = formatLocalDateTime('2026-11-02T10:00:00-05:00', {
        locale: 'en-US',
        timeZone: 'UTC',
      })

      expect(text).toMatch(/3:00/)
      expect(text).toMatch(/UTC/)
    })
  })

  describe('rejects times it cannot place on the timeline', () => {
    it('throws on an ISO string without a zone offset instead of guessing', () => {
      // Without Z or an offset, Date would read this as browser-local time and
      // silently shift the slot.
      expect(() => formatLocalDateTime('2026-11-02T15:00:00')).toThrow(
        RangeError,
      )
    })

    it('throws on an unparseable value', () => {
      expect(() => formatLocalDateTime('not a date')).toThrow(RangeError)
    })
  })
})
