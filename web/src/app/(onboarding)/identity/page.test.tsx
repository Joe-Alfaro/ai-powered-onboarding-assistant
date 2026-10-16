import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { TRIGGERS } from '@/support/triggers'
import { errorEnvelope, headerOf, installFetch } from '@/test-utils/fetch'
import {
  consentResponse,
  documentResponse,
  photoOfId,
  requestsMade,
  routeFetch,
} from '@/test-utils/documents'
import { router, setUpPage } from '@/test-utils/pages'
import IdentityPage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
  usePathname: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

describe('identity page', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    setUpPage()
    fetchMock = installFetch()
  })

  async function consentAndUpload() {
    const user = userEvent.setup()
    render(<IdentityPage />)
    await user.click(screen.getByRole('checkbox', { name: /i agree/i }))
    await user.click(screen.getByRole('button', { name: /continue/i }))
    await user.upload(
      await screen.findByLabelText(/photo of your id/i),
      photoOfId(),
    )
    await user.click(screen.getByRole('button', { name: /^upload/i }))
    return user
  }

  it('sends consent and the upload to the API with the session token', async () => {
    routeFetch(fetchMock, {
      'POST /consents': consentResponse('v'),
      'POST /documents': documentResponse({ id: 'doc-1' }),
    })

    await consentAndUpload()

    await waitFor(() =>
      expect(requestsMade(fetchMock)).toEqual([
        'POST /consents',
        'POST /documents',
      ]),
    )
    fetchMock.mock.calls.forEach(([, init]) => {
      expect(headerOf(init, 'Authorization')).toBe('Bearer session-jwt')
    })
  })

  it('goes to the confirm step for the uploaded document', async () => {
    routeFetch(fetchMock, {
      'POST /consents': consentResponse('v'),
      'POST /documents': documentResponse({ id: 'doc-1' }),
    })

    await consentAndUpload()

    await waitFor(() =>
      expect(router.push).toHaveBeenCalledWith('/confirm?document=doc-1'),
    )
  })

  it('shows the upload-failure supportive content after a rejected upload (R9)', async () => {
    routeFetch(fetchMock, {
      'POST /consents': consentResponse('v'),
      'POST /documents': errorEnvelope(
        415,
        'unsupported_file_type',
        'That file is not a photo.',
        ['manual_entry'],
      ),
    })

    await consentAndUpload()

    const { heading } = TRIGGERS['upload-failure'].content
    expect(
      await within(screen.getByRole('status')).findByRole('heading', {
        name: heading,
      }),
    ).toBeVisible()
    expect(screen.getByRole('alert')).toHaveTextContent(
      'That file is not a photo.',
    )
    expect(router.push).not.toHaveBeenCalled()
  })

  it('skips to manual entry without consent or upload (R10)', async () => {
    const user = userEvent.setup()
    render(<IdentityPage />)

    await user.click(screen.getByRole('button', { name: /skip and enter/i }))

    expect(router.push).toHaveBeenCalledWith('/identity/manual')
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
