import Link from 'next/link'
import type { ReactNode } from 'react'
import { STEPS, type StepId } from './steps'

interface AppShellProps {
  currentStep: StepId | null
  children: ReactNode
}

const MAIN_ID = 'main-content'

// Earlier steps link back; later ones aren't linked, so the nav can't skip
// consent or confirmation. Each state is spelled out in text, not shown by
// color alone (R34).
function StepItem({
  step,
  state,
}: {
  step: (typeof STEPS)[number]
  state: 'completed' | 'current' | 'upcoming'
}) {
  if (state === 'completed') {
    return (
      <li>
        <Link href={step.path}>
          {step.label} <span>(completed)</span>
        </Link>
      </li>
    )
  }
  if (state === 'current') {
    return (
      <li>
        <span aria-current="step">
          {step.label} <span>(current)</span>
        </span>
      </li>
    )
  }
  return (
    <li>
      <span>{step.label}</span>
    </li>
  )
}

export function AppShell({ currentStep, children }: AppShellProps) {
  const currentIndex = STEPS.findIndex(({ id }) => id === currentStep)

  function stateOf(index: number) {
    if (currentIndex === -1 || index > currentIndex) return 'upcoming'
    if (index === currentIndex) return 'current'
    return 'completed'
  }

  return (
    <>
      <a className="skip-link" href={`#${MAIN_ID}`}>
        Skip to main content
      </a>
      <header>
        <p>Onboarding assistant</p>
        <nav aria-label="Onboarding steps">
          <ol>
            {STEPS.map((step, index) => (
              <StepItem key={step.id} step={step} state={stateOf(index)} />
            ))}
          </ol>
        </nav>
      </header>
      <main id={MAIN_ID} tabIndex={-1}>
        {children}
      </main>
    </>
  )
}
