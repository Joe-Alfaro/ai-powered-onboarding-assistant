module Chat
  module Handlers
    # What a handler decides. `llm_reply` is LLM text the handler is willing to use, which still
    # passes through Chat::ReplyGuard; `template` is the handler's own reply, used when there is no
    # usable LLM text. `draft` is the assessment draft after this message.
    Outcome = Data.define(:llm_reply, :template, :draft, :trigger, :scheduling) do
      def initialize(template:, draft:, llm_reply: nil, trigger: nil, scheduling: nil)
        super
      end
    end
  end
end
