'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRef, useState, type FormEvent } from 'react'
import { ErrorNotice } from '@/api/ErrorNotice'
import { ApiError } from '@/api/client'
import { useApiClient } from '@/api/useApiClient'
import { AssessmentSummary } from '@/chat/AssessmentSummary'
import { ChatChoices, choiceLabel } from '@/chat/ChatChoices'
import { Conversation, type Turn } from '@/chat/Conversation'
import {
  choiceParams,
  sendChatMessage,
  withManualEntry,
  type Assessment,
  type ChatChoice,
  type ChoiceParams,
  type SchedulingResult,
} from '@/chat/chatApi'
import { SupportiveContent } from '@/support/SupportiveContent'
import { useStepTriggerEngine } from '@/support/TriggerEngineContext'
import { formatLocalDateTime } from '@/time/formatLocalDateTime'

// The identity step's manual form needs no LLM, so the flow carries on
// without the chat (R16).
const MANUAL_ENTRY_PATH = '/identity/manual'
const NEXT_STEP_PATH = '/identity'

interface FailedSend {
  message: string
  choice?: ChoiceParams
  error: ApiError
}

// What the appointment status shows after a change through the chat. A failed
// outcome shows nothing: its slot is the one asked for, not one the user holds.
function appointmentStatus(scheduling: SchedulingResult) {
  if (scheduling.outcome === 'rescheduled' && scheduling.slot) {
    return `Your appointment is now ${formatLocalDateTime(scheduling.slot.starts_at)}.`
  }
  if (scheduling.outcome === 'cancelled')
    return 'Your appointment is cancelled.'
  return null
}

export default function ChatPage() {
  const router = useRouter()
  const client = useApiClient()
  const { engine, ownsEngine } = useStepTriggerEngine()
  const nextTurnId = useRef(0)
  const field = useRef<HTMLInputElement>(null)
  const [draft, setDraft] = useState('')
  const [turns, setTurns] = useState<Turn[]>([])
  const [sending, setSending] = useState(false)
  const [failed, setFailed] = useState<FailedSend | null>(null)
  const [assessment, setAssessment] = useState<Assessment | null>(null)
  const [replyOffersManualEntry, setReplyOffersManualEntry] = useState(false)
  const [choices, setChoices] = useState<ChatChoice[]>([])
  const [appointment, setAppointment] = useState<string | null>(null)

  function addTurn(speaker: Turn['speaker'], text: string) {
    const id = nextTurnId.current
    nextTurnId.current += 1
    setTurns((current) => [...current, { id, speaker, text }])
  }

  async function deliver(message: string, choice?: ChoiceParams) {
    setSending(true)
    setFailed(null)
    try {
      const response = await sendChatMessage(client, message, choice)
      // A 200 is always a normal reply, the out-of-scope fallback included.
      addTurn('Assistant', response.reply)
      engine.reportChatResponse(response)
      setReplyOffersManualEntry(response.actions.includes('manual_entry'))
      setChoices(response.choices ?? [])
      if (response.scheduling) {
        const status = appointmentStatus(response.scheduling)
        if (status) setAppointment(status)
      }
      // The summary stays once saved; later replies carry assessment: null.
      if (response.assessment) setAssessment(response.assessment)
    } catch (error) {
      if (!(error instanceof ApiError)) throw error
      setFailed({ message, choice, error: withManualEntry(error) })
    } finally {
      setSending(false)
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const message = draft.trim()
    if (!message || sending) return
    addTurn('You', message)
    setDraft('')
    field.current?.focus()
    void deliver(message)
  }

  // The button's label is sent as the message, so the choice reads as the
  // user's own turn (R36).
  function choose(choice: ChatChoice) {
    if (sending) return
    const message = choiceLabel(choice)
    addTurn('You', message)
    void deliver(message, choiceParams(choice))
  }

  function enterManually() {
    router.push(MANUAL_ENTRY_PATH)
  }

  return (
    <>
      <h1>Tell us what you need</h1>
      <form onSubmit={handleSubmit}>
        <label htmlFor="chat-message">Message</label>
        <input
          id="chat-message"
          ref={field}
          type="text"
          autoComplete="off"
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
        />
        <button type="submit">Send</button>
      </form>
      <p role="status">
        {assessment ? 'Assessment complete' : 'Assessment in progress'}
      </p>
      {assessment && (
        <>
          <AssessmentSummary assessment={assessment} />
          <p>
            <Link href={NEXT_STEP_PATH}>Continue to your ID</Link>
          </p>
        </>
      )}
      <Conversation turns={turns} />
      <ChatChoices choices={choices} disabled={sending} onChoose={choose} />
      <div role="status" aria-label="Your appointment">
        {appointment && <p>{appointment}</p>}
      </div>
      {failed && (
        <ErrorNotice
          error={failed.error}
          onRetry={() => void deliver(failed.message, failed.choice)}
          onManualEntry={enterManually}
        />
      )}
      {replyOffersManualEntry && !failed && (
        <button type="button" onClick={enterManually}>
          Enter details manually
        </button>
      )}
      {ownsEngine && <SupportiveContent engine={engine} />}
    </>
  )
}
