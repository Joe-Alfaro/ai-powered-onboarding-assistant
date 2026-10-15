module Llm
  # The provider-neutral entry point for LLM calls. Each call gets a 6 s client timeout, and a
  # timeout, 5xx, 429 or connection failure is retried once on LLM_FALLBACK_PROVIDER when one is
  # set, inside an overall budget that keeps the failure path under R16's 10 s.
  class Client
    TIMEOUT_SECONDS = 6
    # Primary plus fallback, leaving about a second for the rest of the request.
    BUDGET_SECONDS = 9
    # Below this, a fallback attempt is too short to be worth making.
    MIN_FALLBACK_SECONDS = 1

    def self.from_env(env = ENV)
      primary = Providers.adapter_from_env(env, provider_variable: "LLM_PROVIDER", model_variable: "LLM_MODEL")
      if env["LLM_FALLBACK_PROVIDER"].present?
        fallback = Providers.adapter_from_env(env, provider_variable: "LLM_FALLBACK_PROVIDER",
                                                   model_variable: "LLM_FALLBACK_MODEL")
      end
      new(primary: primary, fallback: fallback)
    end

    # primary and fallback respond to #complete(payload, timeout:) and return an Llm::Response.
    def initialize(primary:, fallback: nil)
      @primary = primary
      @fallback = fallback
    end

    def complete(payload)
      raise ArgumentError, "expected an Llm::Payload from Llm::PayloadBuilder" unless payload.is_a?(Payload)

      started = now
      begin
        @primary.complete(payload, timeout: TIMEOUT_SECONDS)
      rescue Error => error
        remaining = BUDGET_SECONDS - (now - started)
        raise unless @fallback && error.fallback? && remaining >= MIN_FALLBACK_SECONDS

        @fallback.complete(payload, timeout: [ TIMEOUT_SECONDS, remaining ].min)
      end
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
