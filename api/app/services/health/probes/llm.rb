module Health
  module Probes
    # Lists the models of the configured LLM_PROVIDER, never a completion, so a probe spends no
    # quota. Any error, including a missing provider config, raises and so reports down. Only the
    # primary provider is probed.
    class Llm
      def initialize(timeout:)
        @timeout = timeout
      end

      # Reads the environment on each call, so switching LLM_PROVIDER switches the probe.
      def call
        ::Llm::Providers.adapter_from_env(ENV, provider_variable: "LLM_PROVIDER", model_variable: "LLM_MODEL")
                        .list_models(timeout: @timeout)
      end
    end
  end
end
