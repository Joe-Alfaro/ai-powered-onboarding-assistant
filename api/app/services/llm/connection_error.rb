module Llm
  # The provider could not be reached (refused, reset, DNS or TLS failure).
  class ConnectionError < Error
    def code
      "llm_unreachable"
    end

    def fallback?
      true
    end

    private

    def default_message
      "The assistant's provider could not be reached."
    end
  end
end
