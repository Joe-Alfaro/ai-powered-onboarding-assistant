module Llm
  # The provider answered with a 429.
  class RateLimitError < Error
    def code
      "llm_rate_limited"
    end

    def fallback?
      true
    end

    private

    def default_message
      "The assistant is getting too many requests."
    end
  end
end
