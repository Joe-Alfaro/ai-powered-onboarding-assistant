module Chat
  module Handlers
    # What a handler gets: the user's message, the validated LLM answer (empty for a chosen choice,
    # which skips the LLM), the user's assessment draft and the choice sent with the message.
    Context = Data.define(:user_id, :message, :draft, :fields, :llm_reply, :booking_id, :slot_id, :cancel)
  end
end
