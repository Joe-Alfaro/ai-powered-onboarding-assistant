import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent, { type UserEvent } from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { emptyResponse, errorEnvelope, installFetch } from '@/test-utils/fetch'
import { tabTo } from '@/test-utils/keyboard'
import { requestsMade, routeFetch, testApiClient } from '@/test-utils/documents'
import { PrivacyControls } from './PrivacyControls'

// R13 endpoints (seam set by these tests; see docs/decisions.md): withdrawing
// consent is DELETE /consents and a deletion request is DELETE /account, each
// 204 on success.
const WITHDRAW = 'DELETE /consents'
const DELETE_ACCOUNT = 'DELETE /account'

const ACTIONS = [
  {
    name: 'withdraw consent',
    open: /withdraw consent/i,
    request: WITHDRAW,
    result: /consent (has been |is )?withdrawn/i,
  },
  {
    name: 'request deletion',
    open: /delete my data/i,
    request: DELETE_ACCOUNT,
    result: /deleted/i,
  },
] as const

describe('PrivacyControls (R13)', () => {
  let fetchMock: jest.Mock
  let user: UserEvent
  const onDeleted = jest.fn()

  beforeEach(() => {
    fetchMock = installFetch()
    routeFetch(fetchMock, {
      [WITHDRAW]: emptyResponse(204),
      [DELETE_ACCOUNT]: emptyResponse(204),
    })
    user = userEvent.setup()
    onDeleted.mockReset()
  })

  function renderControls() {
    return render(
      <PrivacyControls api={testApiClient()} onDeleted={onDeleted} />,
    )
  }

  function confirmation() {
    return screen.getByRole('alertdialog')
  }

  describe.each(ACTIONS)('a user can $name from the app', (action) => {
    it('asks for confirmation first and sends nothing until confirmed', async () => {
      renderControls()

      await user.click(screen.getByRole('button', { name: action.open }))

      expect(confirmation()).toBeVisible()
      expect(confirmation()).toHaveAccessibleName()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it('sends nothing when the user cancels', async () => {
      renderControls()

      await user.click(screen.getByRole('button', { name: action.open }))
      await user.click(
        within(confirmation()).getByRole('button', { name: /cancel/i }),
      )

      expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it(`sends ${action.request} once confirmed and shows a clear result message`, async () => {
      renderControls()

      await user.click(screen.getByRole('button', { name: action.open }))
      await user.click(
        within(confirmation()).getByRole('button', { name: /yes/i }),
      )

      await waitFor(() =>
        expect(screen.getByRole('status')).toHaveTextContent(action.result),
      )
      expect(requestsMade(fetchMock)).toEqual([action.request])
      expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    })

    it('shows the error with a retry when the request fails, and no success message', async () => {
      routeFetch(fetchMock, {
        [action.request]: errorEnvelope(
          503,
          'unavailable',
          'We could not do that right now.',
          ['retry'],
        ),
      })
      renderControls()

      await user.click(screen.getByRole('button', { name: action.open }))
      await user.click(
        within(confirmation()).getByRole('button', { name: /yes/i }),
      )

      const alert = await screen.findByRole('alert')
      expect(alert).toHaveTextContent('We could not do that right now.')
      expect(screen.queryByText(action.result)).not.toBeInTheDocument()
      routeFetch(fetchMock, { [action.request]: emptyResponse(204) })
      await user.click(
        within(alert).getByRole('button', { name: /try again/i }),
      )
      await waitFor(() =>
        expect(screen.getByRole('status')).toHaveTextContent(action.result),
      )
    })
  })

  it('reports a completed deletion to the page, and not a withdrawal', async () => {
    renderControls()

    await user.click(screen.getByRole('button', { name: /withdraw consent/i }))
    await user.click(
      within(confirmation()).getByRole('button', { name: /yes/i }),
    )
    await waitFor(() => expect(requestsMade(fetchMock)).toEqual([WITHDRAW]))
    expect(onDeleted).not.toHaveBeenCalled()

    await user.click(screen.getByRole('button', { name: /delete my data/i }))
    await user.click(
      within(confirmation()).getByRole('button', { name: /yes/i }),
    )
    await waitFor(() => expect(onDeleted).toHaveBeenCalledTimes(1))
  })

  it('explains what each action deletes before the user confirms', async () => {
    renderControls()

    await user.click(screen.getByRole('button', { name: /delete my data/i }))

    expect(confirmation()).toHaveTextContent(/photo|image/i)
    expect(confirmation()).toHaveTextContent(/cannot be undone|permanent/i)
  })

  describe('R34: the privacy controls are accessible and work with the keyboard alone', () => {
    it('has no axe violations, closed and with the confirmation open', async () => {
      const { container } = renderControls()
      expect(await axe(container)).toHaveNoViolations()

      await user.click(screen.getByRole('button', { name: /delete my data/i }))

      expect(await axe(container)).toHaveNoViolations()
    })

    it('moves focus into the confirmation, and back to the button on cancel', async () => {
      renderControls()
      const open = screen.getByRole('button', { name: /withdraw consent/i })

      await tabTo(user, open)
      await user.keyboard('{Enter}')
      expect(confirmation()).toContainElement(
        document.activeElement as HTMLElement,
      )

      await user.keyboard('{Escape}')
      expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
      expect(open).toHaveFocus()
      expect(fetchMock).not.toHaveBeenCalled()
    })

    it('can withdraw consent with the keyboard only', async () => {
      renderControls()

      await tabTo(
        user,
        screen.getByRole('button', { name: /withdraw consent/i }),
      )
      await user.keyboard('{Enter}')
      await tabTo(
        user,
        within(confirmation()).getByRole('button', { name: /yes/i }),
      )
      await user.keyboard('{Enter}')

      await waitFor(() =>
        expect(screen.getByRole('status')).toHaveTextContent(/withdrawn/i),
      )
    })
  })
})
