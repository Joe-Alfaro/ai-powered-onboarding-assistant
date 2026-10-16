import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { installFetch } from '@/test-utils/fetch'
import {
  onboardingResponse,
  requestsMade,
  routeFetch,
} from '@/test-utils/documents'
import { router, setUpPage } from '@/test-utils/pages'
import ManualIdentityPage from './page'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  useSearchParams: jest.fn(),
  usePathname: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const IDENTITY = {
  full_name: 'Jane Q Sample',
  date_of_birth: '1985-03-14',
  address: '123 Fake St, Springfield, ZZ 00000',
}

describe('manual identity page (R10)', () => {
  it('lets the user finish the identity step with no upload, then goes to scheduling', async () => {
    setUpPage()
    const fetchMock = installFetch()
    routeFetch(fetchMock, {
      'POST /onboarding/identity': onboardingResponse(IDENTITY, 'manual'),
    })
    const user = userEvent.setup()
    render(<ManualIdentityPage />)

    await user.type(screen.getByLabelText(/full name/i), IDENTITY.full_name)
    await user.type(
      screen.getByLabelText(/date of birth/i),
      IDENTITY.date_of_birth,
    )
    await user.type(screen.getByLabelText(/address/i), IDENTITY.address)
    await user.click(screen.getByRole('button', { name: /save|continue/i }))

    await waitFor(() => expect(router.push).toHaveBeenCalledWith('/schedule'))
    expect(requestsMade(fetchMock)).toEqual(['POST /onboarding/identity'])
  })
})
