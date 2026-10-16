import { render, screen, waitFor } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { errorEnvelope, installFetch } from '@/test-utils/fetch'
import { tabTo } from '@/test-utils/keyboard'
import {
  jsonBodyOf,
  onboardingResponse,
  requestsMade,
  routeFetch,
  testApiClient,
} from '@/test-utils/documents'
import { ManualIdentityForm } from './ManualIdentityForm'

const IDENTITY = {
  full_name: 'Jane Q Sample',
  date_of_birth: '1985-03-14',
  address: '123 Fake St, Springfield, ZZ 00000',
}

function saveButton() {
  return screen.getByRole('button', { name: /save|continue/i })
}

describe('ManualIdentityForm (R10)', () => {
  let fetchMock: jest.Mock
  let user: UserEvent
  const onSaved = jest.fn()

  beforeEach(() => {
    fetchMock = installFetch()
    routeFetch(fetchMock, {
      'POST /onboarding/identity': onboardingResponse(IDENTITY, 'manual'),
    })
    user = userEvent.setup()
    onSaved.mockReset()
  })

  function renderForm() {
    return render(
      <ManualIdentityForm api={testApiClient()} onSaved={onSaved} />,
    )
  }

  async function fillIn() {
    await user.type(screen.getByLabelText(/full name/i), IDENTITY.full_name)
    await user.type(
      screen.getByLabelText(/date of birth/i),
      IDENTITY.date_of_birth,
    )
    await user.type(screen.getByLabelText(/address/i), IDENTITY.address)
  }

  describe('manual entry is offered for all fields', () => {
    it('shows an empty, labeled field for name, date of birth and address', () => {
      renderForm()

      ;[/full name/i, /date of birth/i, /address/i].forEach((label) => {
        const field = screen.getByLabelText(label)
        expect(field).toHaveValue('')
        expect(field).toBeEnabled()
      })
    })
  })

  describe('a user can finish onboarding without uploading any image', () => {
    it('has no file picker and loads nothing', () => {
      renderForm()

      expect(document.querySelector('input[type="file"]')).toBeNull()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it('saves the typed values with POST /onboarding/identity and nothing else', async () => {
      renderForm()

      await fillIn()
      await user.click(saveButton())

      await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1))
      expect(requestsMade(fetchMock)).toEqual(['POST /onboarding/identity'])
      expect(jsonBodyOf(fetchMock, 'POST /onboarding/identity')).toEqual(
        IDENTITY,
      )
    })

    it('shows the server message and keeps the values when the API rejects them (422)', async () => {
      routeFetch(fetchMock, {
        'POST /onboarding/identity': errorEnvelope(
          422,
          'validation_failed',
          'Please enter your full name.',
          [],
        ),
      })
      renderForm()

      await fillIn()
      await user.click(saveButton())

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'Please enter your full name.',
      )
      expect(onSaved).not.toHaveBeenCalled()
      expect(screen.getByLabelText(/address/i)).toHaveValue(IDENTITY.address)
    })
  })

  describe('R34: the manual entry form is accessible and works with the keyboard alone', () => {
    it('has no axe violations', async () => {
      const { container } = renderForm()

      expect(await axe(container)).toHaveNoViolations()
    })

    it('can be filled in and saved with the keyboard only', async () => {
      renderForm()

      await tabTo(user, screen.getByLabelText(/full name/i))
      await user.keyboard(IDENTITY.full_name)
      await tabTo(user, screen.getByLabelText(/date of birth/i))
      await user.keyboard(IDENTITY.date_of_birth)
      await tabTo(user, screen.getByLabelText(/address/i))
      await user.keyboard(IDENTITY.address)
      await tabTo(user, saveButton())
      await user.keyboard('{Enter}')

      await waitFor(() => expect(onSaved).toHaveBeenCalledTimes(1))
      expect(jsonBodyOf(fetchMock, 'POST /onboarding/identity')).toEqual(
        IDENTITY,
      )
    })
  })
})
