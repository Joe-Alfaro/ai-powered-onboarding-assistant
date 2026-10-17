import { createClient } from '@supabase/supabase-js'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'jest-axe'
import { useRouter } from 'next/navigation'
import { installFetch, jsonResponse } from '@/test-utils/fetch'
import {
  mockSupabase,
  resetMockSupabase,
  sessionFor,
} from '@/test-utils/supabase'
import ChatPage from './page'

jest.mock('@supabase/supabase-js', () => ({ createClient: jest.fn() }))
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(() => '/chat'),
}))

// Rescheduling and cancelling through the chat (R36). The API answers a
// reschedule or cancel request with structured `choices`
// (api/spec/requests/chat_actions_spec.rb); the page shows them as buttons,
// sends the chosen one back, and shows the result. Slot times arrive as UTC
// and show in the browser's zone, America/New_York in Jest, with a zone label
// (R37).

const API_URL = 'https://api.example.test'
const TOKEN = 'access-token-for-tests'
const BOOKING_ID = 'booking-1'

const CURRENT = {
  id: 'slot-current',
  starts_at: '2030-03-04T14:00:00Z',
  ends_at: '2030-03-04T14:30:00Z',
}
const MON_SLOT = {
  id: 'slot-mon',
  starts_at: '2030-03-11T14:00:00Z',
  ends_at: '2030-03-11T14:30:00Z',
}
const TUE_SLOT = {
  id: 'slot-tue',
  starts_at: '2030-03-12T19:30:00Z',
  ends_at: '2030-03-12T20:00:00Z',
}
const WED_SLOT = {
  id: 'slot-wed',
  starts_at: '2030-03-13T13:00:00Z',
  ends_at: '2030-03-13T13:30:00Z',
}
// Before the Mar 10 daylight-saving change, so EST; the rest are EDT.
const CURRENT_TEXT = /Mon, Mar 4, 2030, 9:00\sAM\sEST/
const MON_TEXT = /Mon, Mar 11, 2030, 10:00\sAM\sEDT/
const TUE_TEXT = /Tue, Mar 12, 2030, 3:30\sPM\sEDT/
const WED_TEXT = /Wed, Mar 13, 2030, 9:00\sAM\sEDT/

const ASK_REPLY = 'Here are the open times. Which one would you like?'
const MOVED_REPLY =
  'Your appointment has been moved. The new time is shown below.'
const TAKEN_REPLY =
  'Sorry, that time is no longer available. Please choose another one.'
const CONFIRM_REPLY = 'Do you want me to cancel your appointment?'
const CANCELLED_REPLY = 'Your appointment has been cancelled.'

type Slot = typeof MON_SLOT

function slotChoice(slot: Slot) {
  return { type: 'slot', booking_id: BOOKING_ID, slot }
}

const CONFIRM_CANCEL = { type: 'confirm_cancel', booking_id: BOOKING_ID }

interface ChatReply {
  reply: string
  choices?: unknown[]
  scheduling?: Record<string, unknown> | null
}

function chatReply({ reply, choices = [], scheduling = null }: ChatReply) {
  return jsonResponse(200, {
    reply,
    intent: 'request-reschedule',
    trigger: null,
    actions: [],
    assessment: null,
    scheduling,
    choices,
  })
}

function conversation() {
  return screen.getByRole('log', { name: 'Conversation' })
}

function sentBodies(fetchMock: jest.Mock) {
  return fetchMock.mock.calls.map(([, init]) =>
    JSON.parse(String((init as RequestInit).body)),
  )
}

describe('Chat step page: reschedule and cancel (R36)', () => {
  let fetchMock: jest.Mock
  let user: ReturnType<typeof userEvent.setup>

  beforeAll(() => {
    process.env.NEXT_PUBLIC_API_URL = API_URL
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://project.example.test'
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'anon-key-for-tests'
  })

  beforeEach(() => {
    resetMockSupabase()
    jest
      .mocked(createClient)
      .mockReturnValue(
        mockSupabase as unknown as ReturnType<typeof createClient>,
      )
    mockSupabase.auth.getSession.mockResolvedValue(sessionFor('user-1', TOKEN))
    jest.mocked(useRouter).mockReturnValue({
      push: jest.fn(),
      replace: jest.fn(),
      back: jest.fn(),
      forward: jest.fn(),
      refresh: jest.fn(),
      prefetch: jest.fn(),
    } as unknown as ReturnType<typeof useRouter>)
    fetchMock = installFetch()
    user = userEvent.setup()
  })

  async function send(text: string) {
    await user.type(screen.getByRole('textbox', { name: 'Message' }), text)
    await user.click(screen.getByRole('button', { name: 'Send' }))
  }

  async function askToReschedule() {
    fetchMock.mockResolvedValueOnce(
      chatReply({
        reply: ASK_REPLY,
        choices: [slotChoice(MON_SLOT), slotChoice(TUE_SLOT)],
      }),
    )
    render(<ChatPage />)
    await send('Can I move my appointment?')
    await within(conversation()).findByText(ASK_REPLY)
  }

  describe('slot choices', () => {
    it('R36, R37: shows each offered slot as a button labelled with its local time and zone', async () => {
      await askToReschedule()

      const group = screen.getByRole('group', { name: /choose a new time/i })
      const buttons = within(group).getAllByRole('button')
      expect(buttons).toHaveLength(2)
      expect(buttons[0]).toHaveAccessibleName(MON_TEXT)
      expect(buttons[1]).toHaveAccessibleName(TUE_TEXT)
    })

    it('R34: the choices are reachable and usable with the keyboard alone', async () => {
      await askToReschedule()
      fetchMock.mockResolvedValueOnce(chatReply({ reply: MOVED_REPLY }))

      const tue = screen.getByRole('button', { name: TUE_TEXT })
      for (
        let presses = 0;
        presses < 10 && document.activeElement !== tue;
        presses++
      ) {
        await user.tab()
      }
      expect(tue).toHaveFocus()
      await user.keyboard('{Enter}')

      await within(conversation()).findByText(MOVED_REPLY)
      expect(sentBodies(fetchMock)[1]).toMatchObject({
        booking_id: BOOKING_ID,
        slot_id: TUE_SLOT.id,
      })
    })

    it('R34: the page with choices has no accessibility violations', async () => {
      fetchMock.mockResolvedValueOnce(
        chatReply({ reply: ASK_REPLY, choices: [slotChoice(MON_SLOT)] }),
      )
      const { container } = render(<ChatPage />)

      await send('Can I move my appointment?')
      await screen.findByRole('button', { name: MON_TEXT })

      expect(await axe(container)).toHaveNoViolations()
    })

    it('R36: choosing a slot sends its booking_id and slot_id with the message, and shows the choice in the conversation', async () => {
      await askToReschedule()
      fetchMock.mockResolvedValueOnce(chatReply({ reply: MOVED_REPLY }))

      await user.click(screen.getByRole('button', { name: TUE_TEXT }))

      await within(conversation()).findByText(MOVED_REPLY)
      const [, chosen] = sentBodies(fetchMock)
      expect(chosen).toEqual({
        message: expect.any(String),
        booking_id: BOOKING_ID,
        slot_id: TUE_SLOT.id,
      })
      expect(chosen.message.trim()).not.toBe('')
      expect(chosen).not.toHaveProperty('cancel')
      // The user's choice reads as their own turn, before the reply.
      expect(conversation()).toHaveTextContent(
        new RegExp(`You:.*${TUE_TEXT.source}.*Assistant:.*${MOVED_REPLY}`),
      )
    })

    it('R36, R37: shows the new time from the scheduling result in local time, and removes the choices', async () => {
      await askToReschedule()
      fetchMock.mockResolvedValueOnce(
        chatReply({
          reply: MOVED_REPLY,
          scheduling: {
            outcome: 'rescheduled',
            booking_id: BOOKING_ID,
            slot: TUE_SLOT,
            previous_slot: CURRENT,
          },
        }),
      )

      await user.click(screen.getByRole('button', { name: TUE_TEXT }))
      await within(conversation()).findByText(MOVED_REPLY)

      const status = screen.getByRole('status', { name: /appointment/i })
      expect(status).toHaveTextContent(TUE_TEXT)
      expect(status).not.toHaveTextContent(CURRENT_TEXT)
      expect(
        screen.queryByRole('group', { name: /choose a new time/i }),
      ).not.toBeInTheDocument()
    })

    it('R36: a choice can only be sent once', async () => {
      await askToReschedule()
      let answer: (value: unknown) => void = () => {}
      fetchMock.mockReturnValueOnce(
        new Promise((resolve) => {
          answer = resolve
        }),
      )

      await user.click(screen.getByRole('button', { name: TUE_TEXT }))

      // While the choice is on its way, no choice button can be pressed again.
      const pressable = screen
        .queryAllByRole('button', { name: /2030/ })
        .filter((button) => !(button as HTMLButtonElement).disabled)
      expect(pressable).toHaveLength(0)
      answer(chatReply({ reply: MOVED_REPLY }))

      await within(conversation()).findByText(MOVED_REPLY)
      expect(fetchMock).toHaveBeenCalledTimes(2)
    })

    it('R36, R3: a slot taken in between shows the truthful reply and the fresh choices, never the taken time', async () => {
      await askToReschedule()
      fetchMock.mockResolvedValueOnce(
        chatReply({
          reply: TAKEN_REPLY,
          choices: [slotChoice(TUE_SLOT), slotChoice(WED_SLOT)],
          scheduling: {
            outcome: 'slot_taken',
            booking_id: null,
            slot: MON_SLOT,
            previous_slot: null,
          },
        }),
      )

      await user.click(screen.getByRole('button', { name: MON_TEXT }))
      await within(conversation()).findByText(TAKEN_REPLY)

      const group = screen.getByRole('group', { name: /choose a new time/i })
      const names = within(group)
        .getAllByRole('button')
        .map((button) => button.textContent)
      expect(names).toHaveLength(2)
      expect(names[0]).toMatch(TUE_TEXT)
      expect(names[1]).toMatch(WED_TEXT)
      // The taken slot's time appears only in the user's own turn.
      const outsideLog = (document.body.textContent ?? '').replace(
        conversation().textContent ?? '',
        '',
      )
      expect(outsideLog).not.toMatch(MON_TEXT)
    })
  })

  describe('cancelling', () => {
    async function askToCancel() {
      fetchMock.mockResolvedValueOnce(
        chatReply({ reply: CONFIRM_REPLY, choices: [CONFIRM_CANCEL] }),
      )
      render(<ChatPage />)
      await send('Please cancel my appointment')
      await within(conversation()).findByText(CONFIRM_REPLY)
    }

    it('R36: a confirm_cancel choice shows a button that confirms the cancellation', async () => {
      await askToCancel()

      expect(
        screen.getByRole('button', { name: /yes,? cancel/i }),
      ).toBeVisible()
      expect(fetchMock).toHaveBeenCalledTimes(1)
    })

    it('R36: confirming sends the booking_id with cancel: true and shows the result', async () => {
      await askToCancel()
      fetchMock.mockResolvedValueOnce(
        chatReply({
          reply: CANCELLED_REPLY,
          scheduling: {
            outcome: 'cancelled',
            booking_id: BOOKING_ID,
            slot: null,
            previous_slot: CURRENT,
          },
        }),
      )

      await user.click(screen.getByRole('button', { name: /yes,? cancel/i }))

      expect(
        await within(conversation()).findByText(CANCELLED_REPLY),
      ).toBeVisible()
      const [, confirmed] = sentBodies(fetchMock)
      expect(confirmed).toEqual({
        message: expect.any(String),
        booking_id: BOOKING_ID,
        cancel: true,
      })
      expect(
        screen.queryByRole('button', { name: /yes,? cancel/i }),
      ).not.toBeInTheDocument()
    })
  })
})
