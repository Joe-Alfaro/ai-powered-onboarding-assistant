import { render, screen } from '@testing-library/react'
import { axe } from 'jest-axe'
import NotFound from './not-found'

describe('custom not-found page replaces the Next.js default (R30)', () => {
  it('says the page was not found', () => {
    render(<NotFound />)

    expect(
      screen.getByRole('heading', { level: 1, name: /page not found/i }),
    ).toBeVisible()
  })

  it('links back to the start of onboarding', () => {
    render(<NotFound />)

    expect(
      screen.getByRole('link', { name: /back to the start/i }),
    ).toHaveAttribute('href', '/')
  })

  it('has no accessibility violations (R34)', async () => {
    const { container } = render(<NotFound />)

    expect(await axe(container)).toHaveNoViolations()
  })
})
