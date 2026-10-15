'use client'

import { usePathname } from 'next/navigation'
import type { ReactNode } from 'react'
import { AppShell } from '@/shell/AppShell'
import { stepFromPath } from '@/shell/steps'

export default function OnboardingLayout({
  children,
}: {
  children: ReactNode
}) {
  const pathname = usePathname()

  return <AppShell currentStep={stepFromPath(pathname)}>{children}</AppShell>
}
