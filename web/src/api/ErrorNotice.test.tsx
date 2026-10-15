import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { useEffect, useState } from 'react'
import {
  errorEnvelope,
  hangingFetch,
  installFetch,
  jsonResponse,
} from '@/test-utils/fetch'
import { ApiError, createApiClient } from './client'
import { ErrorNotice } from './ErrorNotice'

function apiError(actions: ApiError['actions']) {
  return new ApiError({
    status: 503,
    code: 'llm_unavailable',
    message: 'The assistant is unavailable right now.',
    actions,
  })
}

describe('ErrorNotice (R16, R30)', () => {
  it('announces the error message as an alert', () => {
    render(<ErrorNotice error={apiError([])} />)

    expect(screen.getByRole('alert')).toHaveTextContent(
      'The assistant is unavailable right now.',
    )
  })

  it('offers "Try again" for a retry action and calls onRetry', async () => {
    const user = userEvent.setup()
    const onRetry = jest.fn()
    render(<ErrorNotice error={apiError(['retry'])} onRetry={onRetry} />)

    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(onRetry).toHaveBeenCalledTimes(1)
    expect(
      screen.queryByRole('button', { name: 'Enter details manually' }),
    ).not.toBeInTheDocument()
  })

  it('offers "Enter details manually" for a manual-entry action and calls onManualEntry', async () => {
    const user = userEvent.setup()
    const onManualEntry = jest.fn()
    render(
      <ErrorNotice
        error={apiError(['manual_entry'])}
        onManualEntry={onManualEntry}
      />,
    )

    await user.click(
      screen.getByRole('button', { name: 'Enter details manually' }),
    )

    expect(onManualEntry).toHaveBeenCalledTimes(1)
    expect(
      screen.queryByRole('button', { name: 'Try again' }),
    ).not.toBeInTheDocument()
  })

  it('offers both choices when the envelope lists both', () => {
    render(
      <ErrorNotice
        error={apiError(['retry', 'manual_entry'])}
        onRetry={jest.fn()}
        onManualEntry={jest.fn()}
      />,
    )

    expect(screen.getByRole('button', { name: 'Try again' })).toBeVisible()
    expect(
      screen.getByRole('button', { name: 'Enter details manually' }),
    ).toBeVisible()
  })

  it('shows no buttons when the error has no actions', () => {
    render(<ErrorNotice error={apiError([])} onRetry={jest.fn()} />)

    expect(screen.queryByRole('button')).not.toBeInTheDocument()
  })

  it('has no accessibility violations (R34)', async () => {
    const { container } = render(
      <ErrorNotice
        error={apiError(['retry', 'manual_entry'])}
        onRetry={jest.fn()}
        onManualEntry={jest.fn()}
      />,
    )

    expect(await axe(container)).toHaveNoViolations()
  })
})

// A minimal page-like consumer: load once, show the notice on failure, retry
// on request. It proves the client and the notice together meet R30.
function SlotsProbe() {
  const [attempt, setAttempt] = useState(0)
  const [error, setError] = useState<ApiError | null>(null)
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    const api = createApiClient({
      baseUrl: 'https://api.example.test',
      getAccessToken: async () => 'token',
    })
    api
      .request('/slots')
      .then(() => setLoaded(true))
      .catch((caught: ApiError) => setError(caught))
  }, [attempt])

  if (loaded) return <p>Slots loaded</p>
  if (!error) return <p>Loading</p>
  return (
    <ErrorNotice
      error={error}
      onRetry={() => {
        setError(null)
        setAttempt((n) => n + 1)
      }}
    />
  )
}

describe('network failure or 503 shows a clear message with retry within 10 s (R30)', () => {
  let fetchMock: jest.Mock

  beforeEach(() => {
    fetchMock = installFetch()
  })

  afterEach(() => {
    jest.useRealTimers()
  })

  it('shows retry within 10 s when the API hangs, and recovers on retry', async () => {
    jest.useFakeTimers()
    const user = userEvent.setup({ advanceTimers: jest.advanceTimersByTime })
    fetchMock
      .mockImplementationOnce(hangingFetch)
      .mockResolvedValueOnce(jsonResponse(200, { slots: [] }))
    render(<SlotsProbe />)

    await act(async () => {
      await jest.advanceTimersByTimeAsync(10_000)
    })

    expect(screen.getByRole('alert')).toHaveTextContent(/.+/)
    await user.click(screen.getByRole('button', { name: 'Try again' }))

    expect(await screen.findByText('Slots loaded')).toBeVisible()
  })

  it('shows a clear message and retry when the network is down', async () => {
    fetchMock.mockRejectedValue(new TypeError('Failed to fetch'))
    render(<SlotsProbe />)

    const alert = await screen.findByRole('alert')

    expect(alert).not.toHaveTextContent('Failed to fetch')
    expect(screen.getByRole('button', { name: 'Try again' })).toBeVisible()
  })

  it("shows the API's 503 message and retry", async () => {
    fetchMock.mockResolvedValue(
      errorEnvelope(
        503,
        'database_unavailable',
        'We are having trouble saving right now.',
        ['retry'],
      ),
    )
    render(<SlotsProbe />)

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'We are having trouble saving right now.',
    )
    expect(screen.getByRole('button', { name: 'Try again' })).toBeVisible()
  })
})
