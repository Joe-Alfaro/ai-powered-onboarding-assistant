import AxeBuilder from '@axe-core/playwright'
import { test as base, expect, type Locator, type Page } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import path from 'node:path'
import { TRIGGERS } from '../../src/support/triggers'
import { API_URL, FAKE_LLM_URL, REPO_ROOT, supabaseLocal } from './stack'

export { expect }

// Distinctive synthetic values: nothing else in the app or its fixtures
// contains them, so finding one in a log can only be a leak (R15).
export const SYNTHETIC = {
  fullName: 'Quillon Zephyrine Marbleworth',
  dateOfBirth: '1979-02-28',
  address: '417 Lanternfish Crescent, Exampleford, ZZ 00417',
  reason: 'relocating my Zanzibarbaroque pottery studio',
}

// Three messages the fake LLM turns into a complete assessment.
export const ASSESSMENT_MESSAGES = [
  `I would like help with ${SYNTHETIC.reason}.`,
  'It is fairly urgent.',
  'Weekday mornings suit me best.',
]

// A golden-set image the OCR reads (R26), and one with no text at all.
export const GOLDEN_IMAGE = path.join(
  REPO_ROOT,
  'api/eval/golden/001_clean.png',
)
export const GOLDEN_NAME = /Templeton/i
export const UNREADABLE_IMAGE = path.join(__dirname, '../fixtures/blank.png')

export type FakeLlmMode = 'normal' | 'server-error' | 'rate-limit' | 'timeout'

export interface TestUser {
  email: string
  password: string
  // A fresh access token, for setting up state through the API.
  token: () => Promise<string>
}

async function setFakeLlmMode(mode: FakeLlmMode) {
  const response = await fetch(`${FAKE_LLM_URL}/__control`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mode }),
  })
  if (!response.ok)
    throw new Error(`fake LLM control failed: ${response.status}`)
}

// A new confirmed user in the local Supabase Auth, so every test starts with
// no onboarding records.
export async function createUser(): Promise<TestUser> {
  const supabase = supabaseLocal()
  const email = `e2e-${randomUUID()}@example.com`
  const password = `e2e-${randomUUID()}`
  const created = await fetch(`${supabase.url}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      apikey: supabase.serviceRoleKey,
      authorization: `Bearer ${supabase.serviceRoleKey}`,
    },
    body: JSON.stringify({ email, password, email_confirm: true }),
  })
  if (!created.ok)
    throw new Error(`creating a test user failed: ${created.status}`)

  async function token() {
    const response = await fetch(
      `${supabase.url}/auth/v1/token?grant_type=password`,
      {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          apikey: supabase.anonKey,
        },
        body: JSON.stringify({ email, password }),
      },
    )
    if (!response.ok)
      throw new Error(`signing in a test user failed: ${response.status}`)
    return ((await response.json()) as { access_token: string }).access_token
  }

  return { email, password, token }
}

// Calls the API as a user, for arranging state a test isn't about.
export async function apiRequest<T>(
  user: TestUser,
  pathname: string,
  init: { method?: string; body?: object } = {},
): Promise<{ status: number; body: T }> {
  const response = await fetch(`${API_URL}${pathname}`, {
    method: init.method ?? 'GET',
    headers: {
      authorization: `Bearer ${await user.token()}`,
      'content-type': 'application/json',
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  })
  return { status: response.status, body: (await response.json()) as T }
}

// Runs an async step for each item, one after another.
export async function inSequence<T>(
  items: readonly T[],
  step: (item: T) => Promise<void>,
) {
  await items.reduce(
    (previous, item) => previous.then(() => step(item)),
    Promise.resolve(),
  )
}

export interface ApiSlot {
  id: string
  starts_at: string
}

export async function openSlots(user: TestUser) {
  return (await apiRequest<{ slots: ApiSlot[] }>(user, '/slots')).body.slots
}

// A complete assessment through the API, so the user's next step is identity.
export async function completeAssessment(user: TestUser) {
  await inSequence(ASSESSMENT_MESSAGES, async (message) => {
    const { status } = await apiRequest(user, '/chat/messages', {
      method: 'POST',
      body: { message },
    })
    expect(status, 'chat message through the fake LLM').toBe(200)
  })
}

// Gets a user to the schedule step through the API: a complete assessment
// and identity entered by hand.
export async function arriveAtSchedule(user: TestUser) {
  await completeAssessment(user)
  const { status } = await apiRequest(user, '/onboarding/identity', {
    method: 'POST',
    body: {
      full_name: SYNTHETIC.fullName,
      date_of_birth: SYNTHETIC.dateOfBirth,
      address: SYNTHETIC.address,
    },
  })
  expect(status, 'manual identity').toBeLessThan(300)
}

export async function signIn(page: Page, user: TestUser) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(user.email)
  await page.getByLabel('Password').fill(user.password)
  await page.getByRole('button', { name: 'Sign in' }).click()
}

// The control that moves on to the next step once the current one is done.
export function continueControl(page: Page) {
  const name = /^continue\b/i
  return page
    .getByRole('main')
    .getByRole('link', { name })
    .or(page.getByRole('main').getByRole('button', { name }))
}

// R9: with no trigger met, none of the trigger table's content is on screen.
export async function expectNoSupportiveContent(page: Page) {
  const headings = Object.values(TRIGGERS).map(({ content }) => content.heading)
  await Promise.all(
    headings.map((heading) =>
      expect(
        page.getByRole('heading', { name: heading }),
        `supportive content "${heading}" with no trigger met`,
      ).toHaveCount(0),
    ),
  )
}

// R34: axe with the WCAG A and AA rules, color contrast included, reporting
// any serious or critical violation.
export async function expectAccessible(page: Page, label: string) {
  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()
  const blocking = results.violations
    .filter(({ impact }) => impact === 'serious' || impact === 'critical')
    .map(({ id, impact, nodes }) => `${id} (${impact}, ${nodes.length} nodes)`)
  // Soft, so one run reports every page that fails.
  expect
    .soft(blocking, `serious or critical axe violations on ${label}`)
    .toEqual([])
}

// Presses Tab until the target has focus, so a test reaches a control the way
// a keyboard user does. Fails if it never gets there.
export async function tabTo(
  page: Page,
  target: Locator,
  pressesLeft = 60,
): Promise<void> {
  await target.waitFor()
  const focused = await target.evaluate(
    (element) => element === document.activeElement,
  )
  if (focused) return
  if (pressesLeft === 0) throw new Error(`could not reach ${target} with Tab`)
  await page.keyboard.press('Tab')
  return tabTo(page, target, pressesLeft - 1)
}

interface Fixtures {
  user: TestUser
  fakeLlm: { setMode: (mode: FakeLlmMode) => Promise<void> }
  // Every console message and uncaught error from the page, as text (R15).
  browserLog: string[]
}

export const test = base.extend<Fixtures>({
  user: async ({}, use) => {
    await use(await createUser())
  },
  // Every test starts and ends with the fake LLM answering normally.
  fakeLlm: [
    async ({}, use) => {
      await setFakeLlmMode('normal')
      await use({ setMode: setFakeLlmMode })
      await setFakeLlmMode('normal')
    },
    { auto: true },
  ],
  browserLog: [
    async ({ context }, use) => {
      const log: string[] = []
      context.on('console', (message) => {
        log.push(`${message.type()}: ${message.text()}`)
      })
      context.on('weberror', (error) => {
        log.push(`pageerror: ${error.error().message}`)
      })
      await use(log)
    },
    { auto: true },
  ],
})
