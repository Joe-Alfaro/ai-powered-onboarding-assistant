import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { errorEnvelope, installFetch } from '@/test-utils/fetch'
import { tabTo } from '@/test-utils/keyboard'
import {
  consentResponse,
  jsonBodyOf,
  requestsMade,
  routeFetch,
  testApiClient,
} from '@/test-utils/documents'
import {
  createTriggerEngine,
  type TriggerEngine,
} from '@/support/triggerEngine'
import { IdentityStep } from './IdentityStep'

// The version shown on the page, read the way a user would see it.
function shownTextVersion() {
  const line = screen.getByText(/consent text version/i)
  const match = /consent text version:?\s*(\S.*)$/i.exec(
    line.textContent?.trim() ?? '',
  )
  expect(match).not.toBeNull()
  return match![1].trim()
}

function consentCheckbox() {
  return screen.getByRole('checkbox', { name: /i agree/i })
}

function continueButton() {
  return screen.getByRole('button', { name: /continue/i })
}

function queryFilePicker() {
  return screen.queryByLabelText(/photo of your id/i)
}

describe('IdentityStep consent (R12)', () => {
  let fetchMock: jest.Mock
  let engine: TriggerEngine
  const onUploaded = jest.fn()
  const onManualEntry = jest.fn()

  beforeEach(() => {
    fetchMock = installFetch()
    engine = createTriggerEngine()
    onUploaded.mockReset()
    onManualEntry.mockReset()
  })

  afterEach(() => engine.stop())

  function renderStep() {
    return render(
      <IdentityStep
        api={testApiClient()}
        engine={engine}
        onUploaded={onUploaded}
        onManualEntry={onManualEntry}
      />,
    )
  }

  describe('before the upload step, the user sees what is collected and why', () => {
    it('lists what is collected: name, date of birth, address and a photo of the ID', () => {
      renderStep()

      const what = screen.getByRole('heading', { name: /what we collect/i })
      expect(what).toBeVisible()
      const consent = screen.getByRole('region', { name: /consent/i })
      expect(consent).toHaveTextContent(/name/i)
      expect(consent).toHaveTextContent(/date of birth/i)
      expect(consent).toHaveTextContent(/address/i)
      expect(consent).toHaveTextContent(/photo/i)
    })

    it('explains why it is collected and how long the photo is kept', () => {
      renderStep()

      expect(screen.getByRole('heading', { name: /why/i })).toBeVisible()
      const consent = screen.getByRole('region', { name: /consent/i })
      expect(consent).toHaveTextContent(/delete/i)
    })

    it('shows the version of the consent text', () => {
      renderStep()

      expect(screen.getByText(/consent text version/i)).toBeVisible()
      expect(shownTextVersion()).not.toBe('')
    })
  })

  describe("the consent control isn't pre-selected", () => {
    it('renders the consent checkbox unchecked', () => {
      renderStep()

      expect(consentCheckbox()).not.toBeChecked()
    })

    it('does not send consent or continue when the box is not ticked', async () => {
      const user = userEvent.setup()
      renderStep()

      await user.click(continueButton())

      expect(fetchMock).not.toHaveBeenCalled()
      expect(queryFilePicker()).not.toBeInTheDocument()
    })
  })

  describe('upload is unreachable until consent is given and POST /consents succeeds', () => {
    it('shows no file picker or upload button before consent', () => {
      renderStep()

      expect(queryFilePicker()).not.toBeInTheDocument()
      expect(
        screen.queryByRole('button', { name: /^upload/i }),
      ).not.toBeInTheDocument()
    })

    it('posts the shown text version to /consents, then shows the upload step', async () => {
      const user = userEvent.setup()
      renderStep()
      const version = shownTextVersion()
      routeFetch(fetchMock, { 'POST /consents': consentResponse(version) })

      await user.click(consentCheckbox())
      await user.click(continueButton())

      expect(await screen.findByLabelText(/photo of your id/i)).toBeVisible()
      expect(requestsMade(fetchMock)).toEqual(['POST /consents'])
      expect(jsonBodyOf(fetchMock, 'POST /consents')).toEqual({
        text_version: version,
      })
    })

    it('stays on consent and shows the error when POST /consents fails', async () => {
      const user = userEvent.setup()
      renderStep()
      routeFetch(fetchMock, {
        'POST /consents': errorEnvelope(
          422,
          'validation_failed',
          'We could not record your consent.',
          [],
        ),
      })

      await user.click(consentCheckbox())
      await user.click(continueButton())

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'We could not record your consent.',
      )
      expect(queryFilePicker()).not.toBeInTheDocument()
    })

    it('offers a retry when consent could not be sent, and continues once it succeeds', async () => {
      const user = userEvent.setup()
      renderStep()
      const version = shownTextVersion()
      fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))

      await user.click(consentCheckbox())
      await user.click(continueButton())
      const alert = await screen.findByRole('alert')
      routeFetch(fetchMock, { 'POST /consents': consentResponse(version) })
      await user.click(
        within(alert).getByRole('button', { name: /try again/i }),
      )

      expect(await screen.findByLabelText(/photo of your id/i)).toBeVisible()
    })
  })

  describe("R10: 'skip and enter manually' is available before consent", () => {
    it('lets the user skip to manual entry without consenting or uploading', async () => {
      const user = userEvent.setup()
      renderStep()

      await user.click(screen.getByRole('button', { name: /skip and enter/i }))

      expect(onManualEntry).toHaveBeenCalledTimes(1)
      expect(fetchMock).not.toHaveBeenCalled()
    })
  })

  describe('R34: the consent form is accessible and works with the keyboard alone', () => {
    it('has no axe violations', async () => {
      const { container } = renderStep()

      expect(await axe(container)).toHaveNoViolations()
    })

    it('can be ticked and submitted with the keyboard only', async () => {
      const user = userEvent.setup()
      renderStep()
      routeFetch(fetchMock, {
        'POST /consents': consentResponse(shownTextVersion()),
      })

      await tabTo(user, consentCheckbox())
      await user.keyboard(' ')
      expect(consentCheckbox()).toBeChecked()
      await tabTo(user, continueButton())
      await user.keyboard('{Enter}')

      expect(await screen.findByLabelText(/photo of your id/i)).toBeVisible()
    })
  })
})
