module Llm
  # The provider rejected the request with a 4xx other than 429.
  class RequestError < Error
    def code
      "llm_request_rejected"
    end

    private

    def default_message
      "The assistant's provider rejected the request."
    end
  end
end
