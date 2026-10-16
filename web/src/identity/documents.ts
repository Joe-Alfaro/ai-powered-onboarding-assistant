// The documents API's shapes and the identity fields both identity forms show.

export type IdentityFieldName = 'full_name' | 'date_of_birth' | 'address'

export interface FieldReading {
  value: string
  confidence: number
  level: 'high' | 'low'
}

// A null field is one OCR could not read; it is never filled with a guess (R11).
export type DraftFields = Record<IdentityFieldName, FieldReading | null>

export interface IdentityDocument {
  id: string
  status: string
  manual_entry: boolean
  reason: string
  fields: DraftFields
}

export interface DocumentEnvelope {
  document: IdentityDocument
}

export type IdentityValues = Record<IdentityFieldName, string>

export interface IdentityField {
  name: IdentityFieldName
  label: string
  autoComplete: string
  hint?: string
}

export const IDENTITY_FIELDS: readonly IdentityField[] = [
  { name: 'full_name', label: 'Full name', autoComplete: 'name' },
  {
    name: 'date_of_birth',
    label: 'Date of birth',
    autoComplete: 'bday',
    hint: 'Use the format YYYY-MM-DD.',
  },
  { name: 'address', label: 'Address', autoComplete: 'street-address' },
]

// The values exactly as typed, so edits are sent as edited (R5).
export function identityValuesOf(form: HTMLFormElement): IdentityValues {
  const data = new FormData(form)
  return {
    full_name: String(data.get('full_name') ?? ''),
    date_of_birth: String(data.get('date_of_birth') ?? ''),
    address: String(data.get('address') ?? ''),
  }
}
