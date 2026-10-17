import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import GlobalError from './global-error'

const INTERNAL_DETAIL =
  'TypeError: cannot read properties of undefined (layout)'

// global-error.tsx replaces the root layout when the root layout itself throws,
// so it renders its own <html> and <body>. React renders those into the
// document's existing elements.
function renderGlobalError(retry = jest.fn()) {
  const error = Object.assign(new Error(INTERNAL_DETAIL), { digest: 'def456' })
  render(<GlobalError error={error} retry={retry} reset={jest.fn()} />, {
    container: document,
  })
  return retry
}

describe('custom root error page replaces the Next.js default (R30)', () => {
  it('renders its own html element with a language, since the root layout is gone', () => {
    renderGlobalError()

    expect(document.documentElement).toHaveAttribute('lang', 'en')
  })

  it('explains that something went wrong in plain language', () => {
    renderGlobalError()

    expect(
      screen.getByRole('heading', { level: 1, name: /something went wrong/i }),
    ).toBeVisible()
  })

  it('offers a retry', async () => {
    const user = userEvent.setup()
    const retry = renderGlobalError()

    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(retry).toHaveBeenCalledTimes(1)
  })

  it('does not show internal error details', () => {
    renderGlobalError()

    expect(document.body).not.toHaveTextContent(INTERNAL_DETAIL)
    expect(document.body).not.toHaveTextContent('def456')
  })

  it('has no accessibility violations (R34)', async () => {
    renderGlobalError()

    expect(await axe(document.body)).toHaveNoViolations()
  })
})
