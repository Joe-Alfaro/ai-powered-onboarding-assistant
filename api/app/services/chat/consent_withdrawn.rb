module Chat
  # The user withdrew consent or asked for deletion, so chat makes no LLM call (R13).
  class ConsentWithdrawn < StandardError
    def initialize(message = "Consent was withdrawn, so the assistant can't process messages.")
      super
    end
  end
end
