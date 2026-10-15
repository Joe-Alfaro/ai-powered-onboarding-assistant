module Llm
  # The structured output of one LLM call, with the provider and model that produced it.
  Response = Data.define(:data, :provider, :model)
end
