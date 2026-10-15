module Chat
  module Handlers
    # What a handler gets: the validated LLM answer, the user's assessment draft and the booking
    # choice sent with the message.
    Context = Data.define(:user_id, :draft, :fields, :llm_reply, :booking_id, :slot_id)
  end
end
