module Chat
  module Handlers
    # A fixed, polite redirect to onboarding (R3). The LLM's text is never used, so off-topic and
    # injected requests get nothing from it.
    class OutOfScope < Base
      REPLY = "I can only help with your onboarding here: sharing what brings you here, your " \
              "appointment, or questions about getting started. What would you like to do next?".freeze

      def call
        Outcome.new(template: REPLY, draft: context.draft)
      end
    end
  end
end
