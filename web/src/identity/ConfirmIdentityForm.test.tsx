import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { errorEnvelope, installFetch } from '@/test-utils/fetch'
import { tabTo } from '@/test-utils/keyboard'
import {
  CLEAN_FIELDS,
  PARTIAL_FIELDS,
  documentResponse,
  jsonBodyOf,
  onboardingResponse,
  requestsMade,
  routeFetch,
  testApiClient,
  type DocumentFields,
} from '@/test-utils/documents'
import { ConfirmIdentityForm } from './ConfirmIdentityForm'

const DOC_ID = 'doc-7f2c'
const CONFIRM = `POST /documents/${DOC_ID}/confirm`

const EDITED = {
  full_name: 'Janet Q Sample',
  date_of_birth: '1985-03-15',
  address: '125 Fake St, Springfield, ZZ 00001',
}

function nameField() {
  return screen.getByLabelText(/full name/i)
}

function dobField() {
  return screen.getByLabelText(/date of birth/i)
}

function addressField() {
  return screen.getByLabelText(/address/i)
}

function saveButton() {
  return screen.getByRole('button', { name: /confirm/i })
}

async function replaceValue(
  user: UserEvent,
  field: HTMLElement,
  value: string,
) {
  await user.clear(field)
  await user.type(field, value)
}

describe('ConfirmIdentityForm (R5, R11)', () => {
  let fetchMock: jest.Mock
  let user: UserEvent
  const onConfirmed = jest.fn()
  const onManualEntry = jest.fn()

  beforeEach(() => {
    fetchMock = installFetch()
    user = userEvent.setup()
    onConfirmed.mockReset()
    onManualEntry.mockReset()
  })

  async function renderWith(fields: DocumentFields) {
    routeFetch(fetchMock, {
      [`GET /documents/${DOC_ID}`]: documentResponse({ id: DOC_ID, fields }),
      [CONFIRM]: (init) =>
        onboardingResponse(JSON.parse(String(init?.body)), 'ocr'),
    })
    const view = render(
      <ConfirmIdentityForm
        api={testApiClient()}
        documentId={DOC_ID}
        onConfirmed={onConfirmed}
        onManualEntry={onManualEntry}
      />,
    )
    await screen.findByLabelText(/full name/i)
    return view
  }

  describe('R5: every extracted field is shown in an editable form before anything is saved', () => {
    it('loads the draft with GET /documents/:id and shows each field, editable', async () => {
      await renderWith(CLEAN_FIELDS)

      expect(nameField()).toHaveValue('Jane Q Sample')
      expect(dobField()).toHaveValue('1985-03-14')
      expect(addressField()).toHaveValue('123 Fake St, Springfield, ZZ 00000')
      ;[nameField(), dobField(), addressField()].forEach((field) => {
        expect(field).toBeEnabled()
        expect(field).not.toHaveAttribute('readonly')
      })
    })

    it('saves nothing until the user confirms', async () => {
      await renderWith(CLEAN_FIELDS)

      expect(requestsMade(fetchMock)).toEqual([`GET /documents/${DOC_ID}`])
      expect(onConfirmed).not.toHaveBeenCalled()
    })
  })

  describe('R5: values the user edits are submitted as edited', () => {
    it('posts the edited values to /documents/:id/confirm', async () => {
      await renderWith(CLEAN_FIELDS)

      await replaceValue(user, nameField(), EDITED.full_name)
      await replaceValue(user, dobField(), EDITED.date_of_birth)
      await replaceValue(user, addressField(), EDITED.address)
      await user.click(saveButton())

      await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1))
      expect(jsonBodyOf(fetchMock, CONFIRM)).toEqual(EDITED)
    })

    it('posts the OCR values unchanged when the user confirms without editing', async () => {
      await renderWith(CLEAN_FIELDS)

      await user.click(saveButton())

      await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1))
      expect(jsonBodyOf(fetchMock, CONFIRM)).toEqual({
        full_name: 'Jane Q Sample',
        date_of_birth: '1985-03-14',
        address: '123 Fake St, Springfield, ZZ 00000',
      })
    })

    it('posts a value the user typed into a field OCR could not read', async () => {
      await renderWith(PARTIAL_FIELDS)

      await user.type(dobField(), '1985-03-14')
      await user.click(saveButton())

      await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1))
      expect(jsonBodyOf(fetchMock, CONFIRM)).toEqual({
        full_name: 'Jane Q Sample',
        date_of_birth: '1985-03-14',
        address: '123 Fake St',
      })
    })

    it('shows the server message and stays on the form when confirm is rejected (422)', async () => {
      await renderWith(CLEAN_FIELDS)
      routeFetch(fetchMock, {
        [CONFIRM]: errorEnvelope(
          422,
          'validation_failed',
          'Date of birth must be a real date in the past.',
          [],
        ),
      })

      await user.click(saveButton())

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'Date of birth must be a real date in the past.',
      )
      expect(onConfirmed).not.toHaveBeenCalled()
      expect(nameField()).toHaveValue('Jane Q Sample')
    })
  })

  describe('R11: OCR-read fields are marked as needing confirmation by text or icon, not color alone', () => {
    it('describes every pre-filled field as needing confirmation, in visible text', async () => {
      await renderWith(CLEAN_FIELDS)

      ;[nameField(), dobField(), addressField()].forEach((field) => {
        expect(field).toHaveAccessibleDescription(/needs confirmation/i)
      })
      screen.getAllByText(/needs confirmation/i).forEach((marker) => {
        expect(marker).toBeVisible()
      })
    })
  })

  describe('R11: missing fields are blank, never filled', () => {
    it('leaves a field OCR did not read empty and says so', async () => {
      await renderWith(PARTIAL_FIELDS)

      expect(dobField()).toHaveValue('')
      expect(dobField()).toHaveAccessibleDescription(/could not read/i)
      expect(dobField()).not.toHaveAccessibleDescription(/needs confirmation/i)
    })

    it('fills nothing in when OCR read no field at all', async () => {
      await renderWith({ full_name: null, date_of_birth: null, address: null })

      expect(nameField()).toHaveValue('')
      expect(dobField()).toHaveValue('')
      expect(addressField()).toHaveValue('')
    })
  })

  describe('R11: low-confidence fields are marked differently from high-confidence ones', () => {
    it('marks the low-confidence field as low and the high-confidence field as high, in text', async () => {
      await renderWith(PARTIAL_FIELDS)

      expect(addressField()).toHaveAccessibleDescription(/low confidence/i)
      expect(nameField()).toHaveAccessibleDescription(/high confidence/i)
      expect(nameField()).not.toHaveAccessibleDescription(/low confidence/i)
      expect(screen.getByText(/low confidence/i)).toBeVisible()
    })
  })

  describe("R10: 'skip and enter manually' is always available", () => {
    it('offers manual entry on the confirm form', async () => {
      await renderWith(CLEAN_FIELDS)

      await user.click(screen.getByRole('button', { name: /skip and enter/i }))

      expect(onManualEntry).toHaveBeenCalledTimes(1)
      expect(requestsMade(fetchMock)).not.toContain(CONFIRM)
    })

    it('offers manual entry when the draft is gone (404 after the upload expired)', async () => {
      routeFetch(fetchMock, {
        [`GET /documents/${DOC_ID}`]: errorEnvelope(
          404,
          'not_found',
          'That upload has expired.',
          [],
        ),
      })
      render(
        <ConfirmIdentityForm
          api={testApiClient()}
          documentId={DOC_ID}
          onConfirmed={onConfirmed}
          onManualEntry={onManualEntry}
        />,
      )

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'That upload has expired.',
      )
      await user.click(screen.getByRole('button', { name: /skip and enter/i }))
      expect(onManualEntry).toHaveBeenCalledTimes(1)
    })

    it('offers a retry when the draft could not be loaded, and shows it once loaded', async () => {
      fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))
      render(
        <ConfirmIdentityForm
          api={testApiClient()}
          documentId={DOC_ID}
          onConfirmed={onConfirmed}
          onManualEntry={onManualEntry}
        />,
      )
      const alert = await screen.findByRole('alert')
      routeFetch(fetchMock, {
        [`GET /documents/${DOC_ID}`]: documentResponse({ id: DOC_ID }),
      })

      await user.click(
        within(alert).getByRole('button', { name: /try again/i }),
      )

      expect(await screen.findByLabelText(/full name/i)).toHaveValue(
        'Jane Q Sample',
      )
    })
  })

  describe('R34: the confirm form is accessible and works with the keyboard alone', () => {
    it('has no axe violations with partial, low-confidence results', async () => {
      const { container } = await renderWith(PARTIAL_FIELDS)

      expect(await axe(container)).toHaveNoViolations()
    })

    it('can be edited and confirmed with the keyboard only', async () => {
      await renderWith(PARTIAL_FIELDS)

      await tabTo(user, dobField())
      await user.keyboard('1985-03-14')
      await tabTo(user, saveButton())
      await user.keyboard('{Enter}')

      await waitFor(() => expect(onConfirmed).toHaveBeenCalledTimes(1))
      expect(jsonBodyOf(fetchMock, CONFIRM)).toMatchObject({
        date_of_birth: '1985-03-14',
      })
    })
  })
})
