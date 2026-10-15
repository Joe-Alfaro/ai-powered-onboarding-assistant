module Llm
  # The provider answered with a 5xx.
  class ServerError < Error
    def code
      "llm_server_error"
    end

    def fallback?
      true
    end

    private

    def default_message
      "The assistant's provider had an error."
    end
  end
end
