import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { SupportiveContent } from '@/support/SupportiveContent'
import {
  createTriggerEngine,
  type TriggerEngine,
} from '@/support/triggerEngine'
import { TRIGGERS } from '@/support/triggers'
import {
  errorEnvelope,
  htmlResponse,
  installFetch,
  type FakeResponse,
} from '@/test-utils/fetch'
import { tabTo } from '@/test-utils/keyboard'
import {
  MB,
  PARTIAL_FIELDS,
  consentResponse,
  documentBody,
  documentResponse,
  fileOfSize,
  manualEntryResponse,
  photoOfId,
  requestsMade,
  routeFetch,
  testApiClient,
} from '@/test-utils/documents'
import { IdentityStep } from './IdentityStep'

const UPLOAD_FAILURE = TRIGGERS['upload-failure'].content

function filePicker() {
  return screen.getByLabelText(/photo of your id/i)
}

function uploadButton() {
  return screen.getByRole('button', { name: /^upload/i })
}

function skipButton() {
  return screen.getByRole('button', { name: /skip and enter/i })
}

function expectUploadFailureContent() {
  const status = screen.getByRole('status')
  expect(
    within(status).getByRole('heading', { name: UPLOAD_FAILURE.heading }),
  ).toBeVisible()
}

describe('IdentityStep upload (R9, R10, R14, R34)', () => {
  let fetchMock: jest.Mock
  let engine: TriggerEngine
  let user: UserEvent
  const onUploaded = jest.fn()
  const onManualEntry = jest.fn()
  const originalLimit = process.env.NEXT_PUBLIC_MAX_UPLOAD_MB

  beforeEach(() => {
    fetchMock = installFetch()
    engine = createTriggerEngine()
    engine.start()
    user = userEvent.setup()
    onUploaded.mockReset()
    onManualEntry.mockReset()
    delete process.env.NEXT_PUBLIC_MAX_UPLOAD_MB
  })

  afterEach(() => {
    engine.stop()
    if (originalLimit === undefined) {
      delete process.env.NEXT_PUBLIC_MAX_UPLOAD_MB
    } else {
      process.env.NEXT_PUBLIC_MAX_UPLOAD_MB = originalLimit
    }
  })

  // Renders the step with the trigger engine's content beside it, as the page
  // does, and gives consent so the upload form is showing.
  async function renderConsented(
    uploadResponse: FakeResponse | (() => FakeResponse),
  ) {
    routeFetch(fetchMock, {
      'POST /consents': consentResponse('test-version'),
      'POST /documents':
        typeof uploadResponse === 'function'
          ? uploadResponse
          : () => uploadResponse,
    })
    const view = render(
      <>
        <IdentityStep
          api={testApiClient()}
          engine={engine}
          onUploaded={onUploaded}
          onManualEntry={onManualEntry}
        />
        <SupportiveContent engine={engine} />
      </>,
    )
    await user.click(screen.getByRole('checkbox', { name: /i agree/i }))
    await user.click(screen.getByRole('button', { name: /continue/i }))
    await screen.findByLabelText(/photo of your id/i)
    return view
  }

  async function chooseAndUpload(file = photoOfId()) {
    await user.upload(filePicker(), file)
    await user.click(uploadButton())
  }

  describe('a successful upload', () => {
    it('sends the chosen file as multipart field "file" to POST /documents', async () => {
      await renderConsented(documentResponse())
      const file = photoOfId()

      await chooseAndUpload(file)

      await waitFor(() =>
        expect(requestsMade(fetchMock)).toEqual([
          'POST /consents',
          'POST /documents',
        ]),
      )
      const init = fetchMock.mock.calls[1][1] as RequestInit
      expect(init.body).toBeInstanceOf(FormData)
      expect((init.body as FormData).get('file')).toBe(file)
    })

    it('hands the extracted draft to the confirm step and fires no supportive content', async () => {
      await renderConsented(documentResponse({ fields: PARTIAL_FIELDS }))

      await chooseAndUpload()

      await waitFor(() =>
        expect(onUploaded).toHaveBeenCalledWith(
          documentBody({ fields: PARTIAL_FIELDS }),
        ),
      )
      expect(onManualEntry).not.toHaveBeenCalled()
      expect(engine.active()).toEqual([])
    })
  })

  describe('R14: a 4xx envelope from a bad file shows the server message and fires upload-failure (R9)', () => {
    it.each([
      [
        'a renamed non-image',
        415,
        'unsupported_file_type',
        'That file is not a photo. Please upload a JPEG, PNG or HEIC image.',
      ],
      [
        'a truncated or corrupt image',
        422,
        'unreadable_image',
        'We could not open that image. It may be damaged; please try another photo.',
      ],
      [
        'an oversized file',
        413,
        'file_too_large',
        'That file is over the 10 MB limit. Please choose a smaller photo.',
      ],
    ])('%s (%i %s)', async (_case, status, code, message) => {
      await renderConsented(
        errorEnvelope(status, code, message, ['manual_entry']),
      )

      await chooseAndUpload()

      expect(await screen.findByRole('alert')).toHaveTextContent(message)
      expect(engine.active()).toContain('upload-failure')
      expectUploadFailureContent()
      expect(onUploaded).not.toHaveBeenCalled()
    })

    it('lets the user try another photo after a rejection', async () => {
      let attempt = 0
      await renderConsented(() => {
        attempt += 1
        return attempt === 1
          ? errorEnvelope(
              415,
              'unsupported_file_type',
              'That file is not a photo.',
              ['manual_entry'],
            )
          : documentResponse()
      })

      await chooseAndUpload(photoOfId('notes.jpg'))
      await screen.findByRole('alert')
      await chooseAndUpload(photoOfId('id.jpg'))

      await waitFor(() =>
        expect(onUploaded).toHaveBeenCalledWith(documentBody()),
      )
    })
  })

  describe('a failed upload never shows a 500 page', () => {
    it.each([
      [
        'a 500 HTML page',
        () => htmlResponse(500, '<h1>Internal Server Error</h1>'),
      ],
      [
        'a 503 envelope',
        () =>
          errorEnvelope(503, 'unavailable', 'Uploads are paused right now.', [
            'retry',
          ]),
      ],
    ])(
      'shows a friendly retry for %s and stays on the form',
      async (_case, respond) => {
        await renderConsented(respond)

        await chooseAndUpload()

        const alert = await screen.findByRole('alert')
        expect(alert).not.toHaveTextContent(/internal server error/i)
        expect(
          within(alert).getByRole('button', { name: /try again/i }),
        ).toBeVisible()
        expect(filePicker()).toBeVisible()
        expect(skipButton()).toBeVisible()
        expect(engine.active()).toContain('upload-failure')
      },
    )

    it('shows a friendly retry when the network fails, and retrying resends the file', async () => {
      await renderConsented(documentResponse())
      const file = photoOfId()
      await user.upload(filePicker(), file)
      fetchMock.mockRejectedValueOnce(new TypeError('Failed to fetch'))

      await user.click(uploadButton())
      const alert = await screen.findByRole('alert')
      expect(engine.active()).toContain('upload-failure')
      await user.click(
        within(alert).getByRole('button', { name: /try again/i }),
      )

      await waitFor(() =>
        expect(onUploaded).toHaveBeenCalledWith(documentBody()),
      )
      const uploads = fetchMock.mock.calls.filter(
        ([, init]) =>
          (init as RequestInit).method === 'POST' &&
          (init as RequestInit).body instanceof FormData,
      )
      expect(uploads).toHaveLength(2)
      expect((uploads[1][1].body as FormData).get('file')).toBe(file)
    })

    it('returns to the consent step, unticked, when the server says consent is missing (403)', async () => {
      await renderConsented(
        errorEnvelope(
          403,
          'consent_required',
          'Please give consent before uploading a photo.',
          [],
        ),
      )

      await chooseAndUpload()

      expect(
        await screen.findByText(
          'Please give consent before uploading a photo.',
        ),
      ).toBeVisible()
      expect(
        screen.getByRole('checkbox', { name: /i agree/i }),
      ).not.toBeChecked()
      expect(
        screen.queryByLabelText(/photo of your id/i),
      ).not.toBeInTheDocument()
    })
  })

  describe('R10: OCR failure or a low-confidence result offers manual entry for all fields', () => {
    it.each(['ocr_error', 'no_text', 'low_confidence', 'no_fields'])(
      'offers manual entry when the upload comes back with manual_entry (%s)',
      async (reason) => {
        await renderConsented(manualEntryResponse(reason))

        await chooseAndUpload()

        expect(await screen.findByRole('alert')).toHaveTextContent(/manually/i)
        expect(onUploaded).not.toHaveBeenCalled()
        await user.click(skipButton())
        expect(onManualEntry).toHaveBeenCalledTimes(1)
      },
    )

    it('fires upload-failure supportive content when OCR could not read the photo', async () => {
      await renderConsented(manualEntryResponse('ocr_error'))

      await chooseAndUpload()

      await screen.findByRole('alert')
      expect(engine.active()).toContain('upload-failure')
      expectUploadFailureContent()
    })
  })

  describe("R10: 'skip and enter manually' is always available", () => {
    it('is offered on the upload form before any file is chosen', async () => {
      await renderConsented(documentResponse())

      await user.click(skipButton())

      expect(onManualEntry).toHaveBeenCalledTimes(1)
      expect(requestsMade(fetchMock)).toEqual(['POST /consents'])
    })

    it('is still offered after a rejected upload', async () => {
      await renderConsented(
        errorEnvelope(
          422,
          'unreadable_image',
          'We could not open that image.',
          ['manual_entry'],
        ),
      )

      await chooseAndUpload()
      await screen.findByRole('alert')

      await user.click(skipButton())
      expect(onManualEntry).toHaveBeenCalled()
    })
  })

  describe('client-side size hint', () => {
    it('tells the user the size limit next to the file picker (10 MB by default)', async () => {
      await renderConsented(documentResponse())

      expect(filePicker()).toHaveAccessibleDescription(/10 MB/)
    })

    it('uses NEXT_PUBLIC_MAX_UPLOAD_MB when set', async () => {
      process.env.NEXT_PUBLIC_MAX_UPLOAD_MB = '5'
      await renderConsented(documentResponse())

      expect(filePicker()).toHaveAccessibleDescription(/5 MB/)
    })

    it('warns about a file over the limit without sending it', async () => {
      await renderConsented(documentResponse())

      await chooseAndUpload(fileOfSize(11 * MB))

      expect(await screen.findByRole('alert')).toHaveTextContent(/10 MB/)
      expect(requestsMade(fetchMock)).toEqual(['POST /consents'])
      expect(onUploaded).not.toHaveBeenCalled()
    })

    it('sends a file just under the limit', async () => {
      await renderConsented(documentResponse())

      await chooseAndUpload(fileOfSize(10 * MB - 1))

      await waitFor(() =>
        expect(requestsMade(fetchMock)).toContain('POST /documents'),
      )
    })
  })

  describe('R34: the file picker is accessible and usable by keyboard', () => {
    it('is a native file input with a label', async () => {
      await renderConsented(documentResponse())

      expect(filePicker()).toHaveAttribute('type', 'file')
      expect(filePicker()).toBeEnabled()
    })

    it('has no axe violations on the upload form, including after an error', async () => {
      const { container } = await renderConsented(
        errorEnvelope(
          415,
          'unsupported_file_type',
          'That file is not a photo.',
          ['manual_entry'],
        ),
      )
      expect(await axe(container)).toHaveNoViolations()

      await chooseAndUpload()
      await screen.findByRole('alert')

      expect(await axe(container)).toHaveNoViolations()
    })

    it('reaches the picker and the upload button with Tab and uploads with Enter', async () => {
      await renderConsented(documentResponse())

      await tabTo(user, filePicker())
      // Choosing the file itself happens in the browser's own dialog.
      await user.upload(filePicker(), photoOfId())
      await tabTo(user, uploadButton())
      await user.keyboard('{Enter}')

      await waitFor(() =>
        expect(onUploaded).toHaveBeenCalledWith(documentBody()),
      )
    })

    it('reaches the skip button with Tab', async () => {
      await renderConsented(documentResponse())

      await tabTo(user, skipButton())
      await user.keyboard('{Enter}')

      expect(onManualEntry).toHaveBeenCalledTimes(1)
    })
  })
})
