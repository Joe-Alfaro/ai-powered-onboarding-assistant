module Chat
  module Handlers
    # Sets the high-stress-intent trigger (R9), whatever the LLM said, and records distress in the
    # draft even when the LLM leaves the flag out (R2).
    class ExpressDistress < Base
      TRIGGER = "high-stress-intent".freeze
      TEMPLATE = "I'm sorry this feels hard right now. We can take it one step at a time, " \
                 "with no rush.".freeze

      def call
        draft = context.draft.merge(context.fields).merge("distress" => true)
        Outcome.new(llm_reply: context.llm_reply, template: TEMPLATE, draft: draft, trigger: TRIGGER)
      end
    end
  end
end
