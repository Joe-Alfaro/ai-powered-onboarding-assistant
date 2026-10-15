module Chat
  module Handlers
    # Moves a booking through Scheduling::Booker, and only when the message names both the booking
    # and the new slot the user chose in the scheduler. The reply is a template picked by the real
    # result (R3, R36); the time itself goes to the web in `scheduling`, which shows it in the
    # user's zone (R37). The LLM's text is never used.
    class RequestReschedule < Base
      NEEDS_CHOICE = "I can help you move your appointment. Choose a new time in the scheduler and " \
                     "I'll move it for you.".freeze
      REPLIES = {
        rescheduled: "Your appointment has been moved. The new time is shown below.",
        slot_taken: "Sorry, that time is no longer available. Please choose another one in the scheduler.",
        not_found: "I couldn't find that appointment, so nothing was changed. Please check the " \
                   "scheduler and try again."
      }.freeze
      OTHER_SUCCESS = "Your appointment has been updated. The details are shown below.".freeze
      OTHER_FAILURE = "I couldn't change your appointment, so nothing was changed. Please try again " \
                      "from the scheduler.".freeze

      def call
        return Outcome.new(template: NEEDS_CHOICE, draft: context.draft) unless choice?

        result = Scheduling::Booker.new(user_id: context.user_id)
                                   .reschedule(booking_id: context.booking_id, slot_id: context.slot_id)
        Outcome.new(template: reply_for(result), draft: context.draft, scheduling: result.to_h)
      end

      private

      def choice?
        context.booking_id.present? && context.slot_id.present?
      end

      def reply_for(result)
        REPLIES.fetch(result.outcome.to_sym) { result.success? ? OTHER_SUCCESS : OTHER_FAILURE }
      end
    end
  end
end
