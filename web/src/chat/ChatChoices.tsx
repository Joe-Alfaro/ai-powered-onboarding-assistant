import { formatLocalDateTime } from '@/time/formatLocalDateTime'
import type { ChatChoice } from './chatApi'

export const CONFIRM_CANCEL_LABEL = 'Yes, cancel my appointment'

// The text a choice's button shows, which is also sent as the user's message
// so the transcript reads naturally. Slot times show in the browser's zone
// with its label (R37).
export function choiceLabel(choice: ChatChoice) {
  return choice.type === 'slot'
    ? formatLocalDateTime(choice.slot.starts_at)
    : CONFIRM_CANCEL_LABEL
}

interface ChatChoicesProps {
  choices: readonly ChatChoice[]
  disabled: boolean
  onChoose: (choice: ChatChoice) => void
}

// The reply's choices as plain buttons in a named group, so they are reachable
// and usable with the keyboard alone (R34, R36). They stay disabled while a
// message is on its way, so a choice is sent only once.
export function ChatChoices({ choices, disabled, onChoose }: ChatChoicesProps) {
  const slots = choices.filter((choice) => choice.type === 'slot')
  const cancels = choices.filter((choice) => choice.type === 'confirm_cancel')

  return (
    <>
      {slots.length > 0 && (
        <ChoiceGroup
          name="Choose a new time"
          choices={slots}
          disabled={disabled}
          onChoose={onChoose}
        />
      )}
      {cancels.length > 0 && (
        <ChoiceGroup
          name="Confirm cancellation"
          choices={cancels}
          disabled={disabled}
          onChoose={onChoose}
        />
      )}
    </>
  )
}

interface ChoiceGroupProps extends ChatChoicesProps {
  name: string
}

function ChoiceGroup({ name, choices, disabled, onChoose }: ChoiceGroupProps) {
  return (
    <div role="group" aria-label={name}>
      <p>{name}</p>
      <ul>
        {choices.map((choice) => (
          <li key={choiceKey(choice)}>
            <button
              type="button"
              disabled={disabled}
              onClick={() => onChoose(choice)}
            >
              {choiceLabel(choice)}
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}

function choiceKey(choice: ChatChoice) {
  return choice.type === 'slot'
    ? `slot-${choice.slot.id}`
    : `cancel-${choice.booking_id}`
}
