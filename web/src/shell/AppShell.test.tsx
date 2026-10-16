import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { AppShell } from './AppShell'
import { STEPS } from './steps'

function renderShell(currentStep: (typeof STEPS)[number]['id'] | null) {
  return render(
    <AppShell currentStep={currentStep}>
      <h1>Step content</h1>
      <button type="button">Continue</button>
    </AppShell>,
  )
}

function stepNav() {
  return screen.getByRole('navigation', { name: 'Onboarding steps' })
}

function stepItem(label: string) {
  const items = within(stepNav()).getAllByRole('listitem')
  const item = items.find((li) => li.textContent?.includes(label))
  if (!item) throw new Error(`no step item for ${label}`)
  return item
}

describe('AppShell (R34)', () => {
  describe('landmarks', () => {
    it('has a banner naming the app', () => {
      renderShell('chat')

      expect(screen.getByRole('banner')).toHaveTextContent(
        'Onboarding assistant',
      )
    })

    it('renders the page inside the single main landmark', () => {
      renderShell('chat')

      const main = screen.getByRole('main')
      expect(
        within(main).getByRole('heading', { name: 'Step content' }),
      ).toBeVisible()
      expect(screen.getAllByRole('main')).toHaveLength(1)
    })

    it('has a labeled navigation for the steps', () => {
      renderShell('chat')

      expect(stepNav()).toBeVisible()
    })
  })

  describe('step navigation', () => {
    it('lists chat, identity, confirm, schedule and done in order', () => {
      renderShell('chat')

      const list = within(stepNav()).getByRole('list')
      const labels = within(list)
        .getAllByRole('listitem')
        .map((li) => li.textContent ?? '')
      STEPS.forEach((step, index) => {
        expect(labels[index]).toContain(step.label)
      })
      expect(list.tagName).toBe('OL')
    })

    it('marks the current step with aria-current="step" and visible text, not color alone', () => {
      renderShell('confirm')

      const confirm = STEPS.find((step) => step.id === 'confirm')!
      const current = within(stepNav())
        .getAllByText(new RegExp(confirm.label))
        .map((el) => el.closest('[aria-current]'))
        .find(Boolean)
      expect(current).toHaveAttribute('aria-current', 'step')
      expect(stepItem(confirm.label)).toHaveTextContent(/current/i)
      expect(stepNav().querySelectorAll('[aria-current="step"]')).toHaveLength(
        1,
      )
    })

    it('links completed steps back to their pages and says they are completed', () => {
      renderShell('confirm')

      ;['chat', 'identity'].forEach((id) => {
        const step = STEPS.find((s) => s.id === id)!
        const link = within(stepItem(step.label)).getByRole('link')
        expect(link).toHaveAttribute('href', step.path)
        expect(stepItem(step.label)).toHaveTextContent(/completed/i)
      })
    })

    it('does not link to steps the user has not reached', () => {
      renderShell('confirm')

      ;['schedule', 'done'].forEach((id) => {
        const step = STEPS.find((s) => s.id === id)!
        expect(within(stepItem(step.label)).queryByRole('link')).toBeNull()
      })
    })

    it('marks no step current outside the flow', () => {
      renderShell(null)

      expect(stepNav().querySelectorAll('[aria-current]')).toHaveLength(0)
    })
  })

  describe('keyboard', () => {
    it('offers a skip link as the first stop that targets the main content', async () => {
      const user = userEvent.setup()
      renderShell('schedule')

      await user.tab()

      const skip = screen.getByRole('link', { name: 'Skip to main content' })
      expect(skip).toHaveFocus()
      const main = screen.getByRole('main')
      expect(main.id).not.toBe('')
      expect(skip).toHaveAttribute('href', `#${main.id}`)
    })
  })

  describe('arriving at a new step', () => {
    function shellAt(currentStep: (typeof STEPS)[number]['id'] | null) {
      return (
        <AppShell currentStep={currentStep}>
          <h1>Step content</h1>
        </AppShell>
      )
    }

    it('announces nothing and leaves focus alone on the first step shown', () => {
      renderShell('chat')

      expect(screen.getByRole('status')).toBeEmptyDOMElement()
      expect(screen.getByRole('main')).not.toHaveFocus()
    })

    it('names the new step in a live region and moves focus to the main content', () => {
      const { rerender } = render(shellAt('chat'))

      rerender(shellAt('identity'))

      expect(screen.getByRole('status')).toHaveTextContent(
        'Step 2 of 5: Your ID',
      )
      expect(screen.getByRole('main')).toHaveFocus()
    })

    it('keeps focus where it is when leaving the flow', () => {
      const { rerender } = render(shellAt('done'))

      rerender(shellAt(null))

      expect(screen.getByRole('main')).not.toHaveFocus()
    })
  })

  it('has no accessibility violations', async () => {
    const { container } = renderShell('identity')

    expect(await axe(container)).toHaveNoViolations()
  })
})
