module Chat
  module Handlers
    # Reschedules or cancels the user's booking through the chat (R36). A request finds the user's
    # active booking from the token (R19) and answers with structured choices: open slots to move
    # to, or a cancel confirmation. A chosen choice comes back with `booking_id` and `slot_id`, or
    # `booking_id` and `cancel`, and goes to Scheduling::Booker, which checks the booking is the
    # user's. Every reply is a template picked by the real result (R3); times reach the web only in
    # `choices` and `scheduling`, which it shows in the user's zone (R37). The LLM's text is never
    # used.
    class RequestReschedule < Base
      MAX_CHOICES = 5
      CANCEL_REQUEST = /\bcancel/i

      NO_BOOKING = "You don't have an upcoming appointment, so there's nothing to change. You can " \
                   "book one in the scheduler.".freeze
      OFFER = "Here are the open times I can move your appointment to. Choose one below.".freeze
      NO_OTHER_SLOT = "There are no other open times right now, so your appointment stays as it is.".freeze
      CONFIRM_CANCEL = "Do you want me to cancel your appointment? Nothing changes until you confirm.".freeze
      SLOT_UNAVAILABLE = "Sorry, that time is no longer available, so nothing was changed.".freeze
      CHOOSE_ANOTHER = "Please choose another one below.".freeze
      REPLIES = {
        rescheduled: "Your appointment has been moved. The new time is shown below.",
        cancelled: "Your appointment has been cancelled.",
        not_found: "I couldn't find that appointment, so nothing was changed. Please check the " \
                   "scheduler and try again."
      }.freeze
      OTHER_FAILURE = "I couldn't change your appointment, so nothing was changed. Please try again " \
                      "from the scheduler.".freeze

      def call
        return choose_slot if context.booking_id.present? && context.slot_id.present?
        return confirm_cancel if context.booking_id.present? && context.cancel

        booking = Booking.active.find_by(user_id: context.user_id)
        return outcome(NO_BOOKING) unless booking
        return outcome(CONFIRM_CANCEL, choices: [ { type: "confirm_cancel", booking_id: booking.id } ]) if cancel_request?

        offer(booking)
      end

      private

      def cancel_request?
        context.message.to_s.match?(CANCEL_REQUEST)
      end

      def offer(booking)
        choices = slot_choices(booking)
        outcome(choices.empty? ? NO_OTHER_SLOT : OFFER, choices: choices)
      end

      # Slot.open leaves out past and taken slots, the user's own included.
      def slot_choices(booking)
        Slot.open.limit(MAX_CHOICES).map { |slot| { type: "slot", booking_id: booking.id, slot: slot.summary } }
      end

      def choose_slot
        result = booker.reschedule(booking_id: context.booking_id, slot_id: context.slot_id)
        return reply_with(result) unless %i[slot_taken slot_in_past].include?(result.outcome)

        unavailable(result)
      end

      # A taken or past slot: says so, and offers the times still open when the booking is the
      # user's.
      def unavailable(result)
        booking = Booking.active.find_by(user_id: context.user_id, id: context.booking_id)
        choices = booking ? slot_choices(booking) : []
        reply = choices.empty? ? SLOT_UNAVAILABLE : "#{SLOT_UNAVAILABLE} #{CHOOSE_ANOTHER}"
        outcome(reply, choices: choices, scheduling: result.to_h)
      end

      def confirm_cancel
        reply_with(booker.cancel(booking_id: context.booking_id))
      end

      def reply_with(result)
        outcome(REPLIES.fetch(result.outcome, OTHER_FAILURE), scheduling: result.to_h)
      end

      def booker
        Scheduling::Booker.new(user_id: context.user_id)
      end

      def outcome(template, choices: [], scheduling: nil)
        Outcome.new(template: template, draft: context.draft, choices: choices, scheduling: scheduling)
      end
    end
  end
end
