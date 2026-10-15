import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Onboarding assistant',
  description: 'Guided onboarding with ID pre-fill and scheduling',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
