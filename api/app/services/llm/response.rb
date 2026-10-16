module Llm
  # The structured output of one LLM call, with the provider and model that produced it. `usage`
  # is { input_tokens:, output_tokens: } when the provider reports it, else nil; the eval prices
  # calls with it.
  Response = Data.define(:data, :provider, :model, :usage) do
    def initialize(data:, provider:, model:, usage: nil)
      super
    end
  end
end
