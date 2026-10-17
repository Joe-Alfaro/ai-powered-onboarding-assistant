'use client'

import Link from 'next/link'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { STEPS, type StepId } from './steps'

interface AppShellProps {
  currentStep: StepId | null
  onSignOut?: () => void
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

// Moving to a new step puts focus at the top of the main content and names
// the step in a live region, so keyboard and screen reader users start the
// new step where sighted users do (R34). The first step shown isn't
// announced: the page load already is.
function useStepArrival(currentStep: StepId | null) {
  const main = useRef<HTMLElement>(null)
  const [shownStep, setShownStep] = useState(currentStep)
  const [announcement, setAnnouncement] = useState('')
  const index = STEPS.findIndex(({ id }) => id === currentStep)

  // Updated while rendering, the way React derives state from a changed prop.
  if (currentStep !== shownStep) {
    setShownStep(currentStep)
    // Cleared outside the flow, so coming back to the same step is announced.
    setAnnouncement(
      index === -1
        ? ''
        : `Step ${index + 1} of ${STEPS.length}: ${STEPS[index].label}`,
    )
  }

  useEffect(() => {
    if (announcement) main.current?.focus()
  }, [announcement])

  return { main, announcement }
}

export function AppShell({ currentStep, onSignOut, children }: AppShellProps) {
  const currentIndex = STEPS.findIndex(({ id }) => id === currentStep)
  const { main, announcement } = useStepArrival(currentStep)

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
        {onSignOut && (
          <button type="button" onClick={onSignOut}>
            Sign out
          </button>
        )}
        <p role="status" className="visually-hidden">
          {announcement}
        </p>
      </header>
      <main id={MAIN_ID} ref={main} tabIndex={-1}>
        {children}
      </main>
    </>
  )
}
