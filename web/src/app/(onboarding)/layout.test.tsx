import { render, screen, within } from '@testing-library/react'
import { usePathname } from 'next/navigation'
import OnboardingLayout from './layout'

jest.mock('next/navigation', () => ({ usePathname: jest.fn() }))

describe('onboarding layout', () => {
  it('wraps each step page in the app shell with the current step from the route', () => {
    jest.mocked(usePathname).mockReturnValue('/schedule')

    render(
      <OnboardingLayout>
        <h1>Pick a time</h1>
      </OnboardingLayout>,
    )

    expect(
      within(screen.getByRole('main')).getByRole('heading', {
        name: 'Pick a time',
      }),
    ).toBeVisible()
    const nav = screen.getByRole('navigation', { name: 'Onboarding steps' })
    const current = nav.querySelector('[aria-current="step"]')
    expect(current).toHaveTextContent(/schedule/i)
  })
})
