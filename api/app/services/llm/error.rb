module Llm
  # Base class for every LLM failure the user can recover from. The error envelope offers the same
  # two actions for all of them (R16).
  class Error < StandardError
    ACTIONS = %w[try_again continue_manually].freeze

    def initialize(message = nil)
      super(message || default_message)
    end

    def code
      "llm_error"
    end

    def actions
      ACTIONS
    end

    # Whether LLM_FALLBACK_PROVIDER may be tried after this failure. Only failures another
    # provider could plausibly avoid qualify; a rejected or malformed request would fail there too.
    def fallback?
      false
    end

    private

    def default_message
      "The assistant is unavailable right now."
    end
  end
end
