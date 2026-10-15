module Chat
  module Handlers
    # Answers from the FAQ in the system prompt. The template covers a reply the guard rejects,
    # which for a question usually means it was about a time or booking.
    class AskQuestion < Base
      TEMPLATE = "I can't confirm dates, times or bookings in chat. Your appointment details are " \
                 "always shown in the scheduler.".freeze

      def call
        Outcome.new(llm_reply: context.llm_reply, template: TEMPLATE, draft: context.draft)
      end
    end
  end
end
