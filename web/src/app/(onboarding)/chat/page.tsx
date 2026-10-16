'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useRef, useState, type FormEvent } from 'react'
import { ErrorNotice } from '@/api/ErrorNotice'
import { ApiError } from '@/api/client'
import { useApiClient } from '@/api/useApiClient'
import { AssessmentSummary } from '@/chat/AssessmentSummary'
import { Conversation, type Turn } from '@/chat/Conversation'
import {
  sendChatMessage,
  withManualEntry,
  type Assessment,
} from '@/chat/chatApi'
import { SupportiveContent } from '@/support/SupportiveContent'
import { useStepTriggerEngine } from '@/support/TriggerEngineContext'

// The identity step's manual form needs no LLM, so the flow carries on
// without the chat (R16).
const MANUAL_ENTRY_PATH = '/identity/manual'
const NEXT_STEP_PATH = '/identity'

interface FailedSend {
  message: string
  error: ApiError
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

  function addTurn(speaker: Turn['speaker'], text: string) {
    const id = nextTurnId.current
    nextTurnId.current += 1
    setTurns((current) => [...current, { id, speaker, text }])
  }

  async function deliver(message: string) {
    setSending(true)
    setFailed(null)
    try {
      const response = await sendChatMessage(client, message)
      // A 200 is always a normal reply, the out-of-scope fallback included.
      addTurn('Assistant', response.reply)
      engine.reportChatResponse(response)
      setReplyOffersManualEntry(response.actions.includes('manual_entry'))
      // The summary stays once saved; later replies carry assessment: null.
      if (response.assessment) setAssessment(response.assessment)
    } catch (error) {
      if (!(error instanceof ApiError)) throw error
      setFailed({ message, error: withManualEntry(error) })
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
      {failed && (
        <ErrorNotice
          error={failed.error}
          onRetry={() => void deliver(failed.message)}
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
