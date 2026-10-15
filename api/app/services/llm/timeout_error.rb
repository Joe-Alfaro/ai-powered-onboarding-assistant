module Llm
  class TimeoutError < Error
    def code
      "llm_timeout"
    end

    def fallback?
      true
    end

    private

    def default_message
      "The assistant took too long to answer."
    end
  end
end
