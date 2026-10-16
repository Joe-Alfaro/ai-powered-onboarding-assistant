import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { emptyResponse, installFetch } from '@/test-utils/fetch'
import { requestsMade, routeFetch } from '@/test-utils/documents'
import { mockSupabase } from '@/test-utils/supabase'
import { setUpPage } from '@/test-utils/pages'
import PrivacyPage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
  usePathname: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

describe('privacy page (R13)', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    setUpPage()
    fetchMock = installFetch()
    routeFetch(fetchMock, {
      'DELETE /consents': emptyResponse(204),
      'DELETE /account': emptyResponse(204),
    })
  })

  it('has a heading and both controls', () => {
    render(<PrivacyPage />)

    expect(screen.getByRole('heading', { level: 1 })).toBeVisible()
    expect(
      screen.getByRole('button', { name: /withdraw consent/i }),
    ).toBeVisible()
    expect(
      screen.getByRole('button', { name: /delete my data/i }),
    ).toBeVisible()
  })

  it('signs the user out after their data is deleted, keeping the result message', async () => {
    const user = userEvent.setup()
    render(<PrivacyPage />)

    await user.click(screen.getByRole('button', { name: /delete my data/i }))
    await user.click(
      within(screen.getByRole('alertdialog')).getByRole('button', {
        name: /yes/i,
      }),
    )

    await waitFor(() => expect(mockSupabase.auth.signOut).toHaveBeenCalled())
    expect(requestsMade(fetchMock)).toEqual(['DELETE /account'])
    expect(screen.getByRole('status')).toHaveTextContent(/deleted/i)
  })

  it('keeps the user signed in after withdrawing consent', async () => {
    const user = userEvent.setup()
    render(<PrivacyPage />)

    await user.click(screen.getByRole('button', { name: /withdraw consent/i }))
    await user.click(
      within(screen.getByRole('alertdialog')).getByRole('button', {
        name: /yes/i,
      }),
    )

    await waitFor(() =>
      expect(screen.getByRole('status')).toHaveTextContent(/withdrawn/i),
    )
    expect(mockSupabase.auth.signOut).not.toHaveBeenCalled()
  })
})
