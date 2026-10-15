import { createClient } from '@supabase/supabase-js'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import {
  mockSupabase,
  resetMockSupabase,
  sessionFor,
} from '@/test-utils/supabase'
import { SignInForm } from './SignInForm'

jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

const EMAIL = 'demo@example.test'
const PASSWORD = 'correct-horse-battery'

async function fillAndSubmit(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText('Email'), EMAIL)
  await user.type(screen.getByLabelText('Password'), PASSWORD)
  await user.click(screen.getByRole('button', { name: 'Sign in' }))
}

describe('SignInForm', () => {
  beforeAll(() => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
  })

  beforeEach(() => {
    resetMockSupabase()
    jest
      .mocked(createClient)
      .mockReturnValue(
        mockSupabase as unknown as ReturnType<typeof createClient>,
      )
  })

  it('signs in with Supabase email and password and reports success', async () => {
    const user = userEvent.setup()
    const onSignedIn = jest.fn()
    mockSupabase.auth.signInWithPassword.mockResolvedValue(
      sessionFor('user-uuid-1', 'jwt'),
    )
    render(<SignInForm onSignedIn={onSignedIn} />)

    await fillAndSubmit(user)

    expect(mockSupabase.auth.signInWithPassword).toHaveBeenCalledWith({
      email: EMAIL,
      password: PASSWORD,
    })
    expect(onSignedIn).toHaveBeenCalledTimes(1)
    expect(mockSupabase.from).not.toHaveBeenCalled()
  })

  it('shows a clear error and stays on the form when the credentials are wrong', async () => {
    const user = userEvent.setup()
    const onSignedIn = jest.fn()
    mockSupabase.auth.signInWithPassword.mockResolvedValue({
      data: { session: null, user: null },
      error: {
        name: 'AuthApiError',
        message: 'Invalid login credentials',
        status: 400,
      },
    })
    render(<SignInForm onSignedIn={onSignedIn} />)

    await fillAndSubmit(user)

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent(/.+/)
    expect(alert).not.toHaveTextContent(PASSWORD)
    expect(onSignedIn).not.toHaveBeenCalled()
    expect(screen.getByRole('button', { name: 'Sign in' })).toBeEnabled()
  })

  it('shows a clear error with a way to retry when Supabase is unreachable (R30)', async () => {
    const user = userEvent.setup()
    const onSignedIn = jest.fn()
    mockSupabase.auth.signInWithPassword
      .mockRejectedValueOnce(new TypeError('Failed to fetch'))
      .mockResolvedValueOnce(sessionFor('user-uuid-1', 'jwt'))
    render(<SignInForm onSignedIn={onSignedIn} />)

    await fillAndSubmit(user)

    const alert = await screen.findByRole('alert')
    expect(alert).not.toHaveTextContent('Failed to fetch')
    expect(alert).toHaveTextContent(/.+/)

    await user.click(screen.getByRole('button', { name: 'Sign in' }))

    expect(onSignedIn).toHaveBeenCalledTimes(1)
  })

  describe('accessibility (R34)', () => {
    it('labels every control and uses the right input types', () => {
      render(<SignInForm onSignedIn={jest.fn()} />)

      expect(screen.getByLabelText('Email')).toHaveAttribute('type', 'email')
      expect(screen.getByLabelText('Password')).toHaveAttribute(
        'type',
        'password',
      )
    })

    it('can be completed with the keyboard alone', async () => {
      const user = userEvent.setup()
      const onSignedIn = jest.fn()
      mockSupabase.auth.signInWithPassword.mockResolvedValue(
        sessionFor('user-uuid-1', 'jwt'),
      )
      render(<SignInForm onSignedIn={onSignedIn} />)

      await user.tab()
      expect(screen.getByLabelText('Email')).toHaveFocus()
      await user.keyboard(EMAIL)
      await user.tab()
      expect(screen.getByLabelText('Password')).toHaveFocus()
      await user.keyboard(`${PASSWORD}{Enter}`)

      expect(onSignedIn).toHaveBeenCalledTimes(1)
    })

    it('has no accessibility violations, including with an error shown', async () => {
      const user = userEvent.setup()
      mockSupabase.auth.signInWithPassword.mockResolvedValue({
        data: { session: null, user: null },
        error: {
          name: 'AuthApiError',
          message: 'Invalid login credentials',
          status: 400,
        },
      })
      const { container } = render(<SignInForm onSignedIn={jest.fn()} />)

      expect(await axe(container)).toHaveNoViolations()

      await fillAndSubmit(user)
      await screen.findByRole('alert')

      expect(await axe(container)).toHaveNoViolations()
    })
  })
})
