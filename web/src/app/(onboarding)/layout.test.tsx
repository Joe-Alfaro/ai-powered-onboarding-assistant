import { render, screen, within } from '@testing-library/react'
import { usePathname } from 'next/navigation'
import { axe } from 'jest-axe'
import { STEPS } from '@/shell/steps'
import { installFetch } from '@/test-utils/fetch'
import { setUpFlow } from '@/test-utils/flow'
import OnboardingLayout from './layout'

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
  useSearchParams: jest.fn(),
}))
jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))

function stepNav() {
  return screen.getByRole('navigation', { name: 'Onboarding steps' })
}

function renderAt(pathname: string) {
  setUpFlow({ pathname })
  return render(
    <OnboardingLayout>
      <h1>Step page</h1>
    </OnboardingLayout>,
  )
}

describe('onboarding layout', () => {
  beforeEach(() => {
    installFetch()
  })

  it('wraps each step page in the app shell with the current step from the route', async () => {
    renderAt('/schedule')

    await screen.findByRole('heading', { name: 'Step page' })

    expect(
      within(screen.getByRole('main')).getByRole('heading', {
        name: 'Step page',
      }),
    ).toBeVisible()
    const current = stepNav().querySelector('[aria-current="step"]')
    expect(current).toHaveTextContent(/schedule/i)
  })

  describe('step navigation', () => {
    it('lists chat, identity, confirm, schedule and done in that order', async () => {
      renderAt('/chat')
      await screen.findByRole('heading', { name: 'Step page' })

      const labels = within(stepNav())
        .getAllByRole('listitem')
        .map((li) => li.textContent ?? '')
      expect(labels).toHaveLength(5)
      ;[
        'Chat',
        'Your ID',
        'Confirm details',
        'Schedule a call',
        'Done',
      ].forEach((label, index) => expect(labels[index]).toContain(label))
    })

    it('on the done step links every earlier step, in order, to its page', async () => {
      renderAt('/done')
      await screen.findByRole('heading', { name: 'Step page' })

      const links = within(stepNav()).getAllByRole('link')
      expect(links.map((link) => link.getAttribute('href'))).toEqual([
        '/chat',
        '/identity',
        '/confirm',
        '/schedule',
      ])
    })

    it.each([
      ['/chat', 'chat'],
      ['/identity', 'identity'],
      ['/identity/manual', 'identity'],
      ['/confirm', 'confirm'],
      ['/schedule', 'schedule'],
      ['/done', 'done'],
    ])(
      'announces the current step on %s with aria-current and visible text',
      async (pathname, id) => {
        renderAt(pathname)
        await screen.findByRole('heading', { name: 'Step page' })

        const step = STEPS.find((s) => s.id === id)!
        const current = stepNav().querySelectorAll('[aria-current="step"]')
        expect(current).toHaveLength(1)
        expect(current[0]).toHaveTextContent(step.label)
        expect(current[0]).toHaveTextContent(/current/i)
      },
    )

    it('moves the current step when the route changes', async () => {
      const { rerender } = renderAt('/chat')
      await screen.findByRole('heading', { name: 'Step page' })

      jest.mocked(usePathname).mockReturnValue('/identity')
      rerender(
        <OnboardingLayout>
          <h1>Step page</h1>
        </OnboardingLayout>,
      )

      expect(
        stepNav().querySelector('[aria-current="step"]'),
      ).toHaveTextContent('Your ID')
      expect(
        within(stepNav()).getByRole('link', { name: /chat/i }),
      ).toHaveAttribute('href', '/chat')
    })
  })

  it('has no accessibility violations (R34)', async () => {
    const { container } = renderAt('/confirm')
    await screen.findByRole('heading', { name: 'Step page' })

    expect(await axe(container)).toHaveNoViolations()
  })
})
