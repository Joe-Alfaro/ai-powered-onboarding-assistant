// Slot times arrive as UTC ISO strings and are shown in the browser's zone,
// labeled with that zone (R37).

interface FormatOptions {
  locale?: string
  timeZone?: string
}

// A date and time that ends in Z or a numeric offset.
const ZONED_ISO =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/i

export function formatLocalDateTime(
  iso: string,
  { locale, timeZone }: FormatOptions = {},
) {
  // Without a zone, Date reads the string as browser-local time and silently
  // shifts the slot, so refuse it.
  if (!ZONED_ISO.test(iso)) {
    throw new RangeError(`Not an ISO time with a zone offset: ${iso}`)
  }
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) {
    throw new RangeError(`Not a valid time: ${iso}`)
  }
  return new Intl.DateTimeFormat(locale, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZone,
    timeZoneName: 'short',
  }).format(date)
}
