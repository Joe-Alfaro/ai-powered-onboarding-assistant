module Chat
  module Handlers
    # Merges the validated fields into the draft and asks for the next missing one.
    class ProvideDetails < Base
      def call
        draft = context.draft.merge(context.fields)
        Outcome.new(llm_reply: context.llm_reply, template: next_question(draft), draft: draft)
      end
    end
  end
end
