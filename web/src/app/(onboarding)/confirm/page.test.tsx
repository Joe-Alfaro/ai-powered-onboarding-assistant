import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { installFetch } from '@/test-utils/fetch'
import {
  documentResponse,
  onboardingResponse,
  requestsMade,
  routeFetch,
} from '@/test-utils/documents'
import { router, setUpPage } from '@/test-utils/pages'
import ConfirmPage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
  usePathname: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

describe('confirm page (R5)', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    fetchMock = installFetch()
  })

  it('loads the document named in the URL, and goes to scheduling once confirmed', async () => {
    setUpPage('document=doc-1')
    routeFetch(fetchMock, {
      'GET /documents/doc-1': documentResponse({ id: 'doc-1' }),
      'POST /documents/doc-1/confirm': (init) =>
        onboardingResponse(JSON.parse(String(init?.body)), 'ocr'),
    })
    const user = userEvent.setup()
    render(<ConfirmPage />)

    expect(await screen.findByLabelText(/full name/i)).toHaveValue(
      'Jane Q Sample',
    )
    await user.click(screen.getByRole('button', { name: /confirm/i }))

    await waitFor(() => expect(router.push).toHaveBeenCalledWith('/schedule'))
    expect(requestsMade(fetchMock)).toEqual([
      'GET /documents/doc-1',
      'POST /documents/doc-1/confirm',
    ])
  })

  it('goes to manual entry when the user skips (R10)', async () => {
    setUpPage('document=doc-1')
    routeFetch(fetchMock, {
      'GET /documents/doc-1': documentResponse({ id: 'doc-1' }),
    })
    const user = userEvent.setup()
    render(<ConfirmPage />)

    await screen.findByLabelText(/full name/i)
    await user.click(screen.getByRole('button', { name: /skip and enter/i }))

    expect(router.push).toHaveBeenCalledWith('/identity/manual')
  })

  it('offers manual entry, and loads nothing, when the URL names no document', async () => {
    setUpPage('')
    const user = userEvent.setup()
    render(<ConfirmPage />)

    await user.click(
      await screen.findByRole('button', { name: /skip and enter/i }),
    )

    expect(router.push).toHaveBeenCalledWith('/identity/manual')
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
