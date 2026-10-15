module Llm
  # The LLM environment variables are missing or wrong. A deploy problem, not a provider failure,
  # so it is not an Llm::Error and offers no user actions.
  class ConfigError < StandardError; end
end
