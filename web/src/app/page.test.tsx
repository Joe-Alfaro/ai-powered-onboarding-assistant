import { render, screen } from '@testing-library/react'
import { axe } from 'jest-axe'
import Home from './page'

describe('Home', () => {
  it('shows the app heading', () => {
    render(<Home />)

    expect(
      screen.getByRole('heading', { name: 'Onboarding assistant' }),
    ).toBeInTheDocument()
  })

  it('has no accessibility violations', async () => {
    const { container } = render(<Home />)

    expect(await axe(container)).toHaveNoViolations()
  })
})
