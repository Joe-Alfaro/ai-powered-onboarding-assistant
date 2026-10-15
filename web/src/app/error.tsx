'use client'

interface ErrorPageProps {
  error: Error & { digest?: string }
  retry: () => void
  // Next 16 still passes the older reset; retry replaces it.
  reset?: () => void
}

// Replaces the Next.js default error page (R30). The error's message may hold
// internal details, so it is never shown.
export default function ErrorPage({ retry }: ErrorPageProps) {
  return (
    <main>
      <h1>Something went wrong</h1>
      <p>This page could not load. Please try again.</p>
      <button type="button" onClick={retry}>
        Try again
      </button>
    </main>
  )
}
