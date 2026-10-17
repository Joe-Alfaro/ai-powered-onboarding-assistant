'use client'

interface GlobalErrorProps {
  error: Error & { digest?: string }
  retry: () => void
  // Next 16 still passes the older reset; retry replaces it.
  reset?: () => void
}

// Replaces the Next.js default root error page (R30). It shows when the root
// layout itself fails, so it renders its own html and body. The error's message
// may hold internal details, so it is never shown.
export default function GlobalError({ retry }: GlobalErrorProps) {
  return (
    <html lang="en">
      <body>
        <main>
          <h1>Something went wrong</h1>
          <p>This page could not load. Please try again.</p>
          <button type="button" onClick={retry}>
            Try again
          </button>
        </main>
      </body>
    </html>
  )
}
