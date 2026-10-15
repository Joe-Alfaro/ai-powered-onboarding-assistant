module Llm
  # The provider answered, but not with the structured output asked for. The chat layer owns the
  # one validation retry, so this never goes to the fallback provider.
  class InvalidResponseError < Error
    def code
      "llm_invalid_response"
    end

    private

    def default_message
      "The assistant's answer could not be read."
    end
  end
end
