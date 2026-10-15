'use client'

import { useId } from 'react'
import {
  IDENTITY_FIELDS,
  type DraftFields,
  type FieldReading,
} from './documents'

interface IdentityFieldsProps {
  // The OCR draft on the confirm form; absent for manual entry.
  draft?: DraftFields
}

// How a field was read, in visible text so it isn't shown by color alone
// (R11, R34).
function readingStatus(reading: FieldReading | null) {
  if (!reading) return 'Could not read this from your ID. Please type it in.'
  return `Needs confirmation: read from your ID with ${reading.level} confidence.`
}

export function IdentityFields({ draft }: IdentityFieldsProps) {
  const id = useId()

  return (
    <>
      {IDENTITY_FIELDS.map(({ name, label, autoComplete, hint }) => {
        const inputId = `${id}-${name}`
        const hintId = `${inputId}-hint`
        const statusId = `${inputId}-status`
        const describedBy = [hint && hintId, draft && statusId]
          .filter(Boolean)
          .join(' ')
        return (
          <div key={name}>
            <label htmlFor={inputId}>{label}</label>
            {hint && <p id={hintId}>{hint}</p>}
            {draft && <p id={statusId}>{readingStatus(draft[name])}</p>}
            <input
              id={inputId}
              name={name}
              type="text"
              autoComplete={autoComplete}
              defaultValue={draft?.[name]?.value ?? ''}
              aria-describedby={describedBy || undefined}
              required
            />
          </div>
        )
      })}
    </>
  )
}
