import Link from 'next/link'

// Replaces the Next.js default 404 page (R30).
export default function NotFound() {
  return (
    <main>
      <h1>Page not found</h1>
      <p>We could not find the page you were looking for.</p>
      <Link href="/">Back to the start</Link>
    </main>
  )
}
