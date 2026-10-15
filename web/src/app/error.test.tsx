import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import ErrorPage from './error'

const INTERNAL_DETAIL = 'PG::ConnectionBad at 10.0.0.5 for user api_role'

function renderErrorPage(retry = jest.fn()) {
  const error = Object.assign(new Error(INTERNAL_DETAIL), { digest: 'abc123' })
  render(<ErrorPage error={error} retry={retry} reset={jest.fn()} />)
  return retry
}

describe('custom error page replaces the Next.js default (R30)', () => {
  it('explains that something went wrong in plain language', () => {
    renderErrorPage()

    expect(
      screen.getByRole('heading', { level: 1, name: /something went wrong/i }),
    ).toBeVisible()
  })

  it('offers a retry that re-renders the failed segment', async () => {
    const user = userEvent.setup()
    const retry = renderErrorPage()

    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(retry).toHaveBeenCalledTimes(1)
  })

  it('does not show internal error details', () => {
    renderErrorPage()

    expect(screen.queryByText(INTERNAL_DETAIL, { exact: false })).toBeNull()
    expect(document.body).not.toHaveTextContent('PG::ConnectionBad')
  })

  it('has no accessibility violations (R34)', async () => {
    renderErrorPage()

    expect(await axe(document.body)).toHaveNoViolations()
  })
})
