module Llm
  # Maps provider names to adapters from environment variables, so the provider and model change
  # with no code change (R21).
  module Providers
    NAMES = %w[anthropic groq gemini ollama].freeze
    KEY_VARIABLES = { "anthropic" => "CLAUDE_API_KEY", "groq" => "GROQ_API_KEY", "gemini" => "GEMINI_API_KEY" }.freeze
    # Used when LLM_MODEL (or LLM_FALLBACK_MODEL) is unset. Fast, cheap models suit a 6 s timeout.
    DEFAULT_MODELS = {
      "anthropic" => "claude-haiku-4-5",
      "groq" => "openai/gpt-oss-20b",
      "gemini" => "gemini-2.5-flash",
      "ollama" => "llama3.2"
    }.freeze
    BASE_URLS = {
      "groq" => "https://api.groq.com/openai/v1",
      "gemini" => "https://generativelanguage.googleapis.com/v1beta/openai"
    }.freeze
    DEFAULT_OLLAMA_BASE_URL = "http://localhost:11434".freeze

    module_function

    # Providers whose credentials are set, so callers such as the eval harness can skip the rest.
    # Ollama counts only when OLLAMA_BASE_URL is set, since it needs a running server.
    def configured(env)
      NAMES.select do |name|
        variable = KEY_VARIABLES.fetch(name, "OLLAMA_BASE_URL")
        env[variable].present?
      end
    end

    # Builds the adapter named by env[provider_variable], or raises Llm::ConfigError naming the
    # variable to fix. Error messages name variables, never their values.
    def adapter_from_env(env, provider_variable:, model_variable:)
      name = env[provider_variable].to_s.strip
      raise ConfigError, "#{provider_variable} is not set. Set it to one of: #{NAMES.join(', ')}" if name.empty?
      raise ConfigError, "#{provider_variable} must be one of: #{NAMES.join(', ')}" unless name.in?(NAMES)

      model = env[model_variable].presence || DEFAULT_MODELS.fetch(name)
      build(name, model, env)
    end

    def build(name, model, env)
      case name
      when "anthropic" then Adapters::Anthropic.new(api_key: key(name, env), model: model)
      when "ollama"
        base_url = env["OLLAMA_BASE_URL"].presence || DEFAULT_OLLAMA_BASE_URL
        Adapters::OpenAiCompatible.new(provider: name, base_url: "#{base_url.delete_suffix('/')}/v1", api_key: nil, model: model)
      else
        Adapters::OpenAiCompatible.new(provider: name, base_url: BASE_URLS.fetch(name), api_key: key(name, env), model: model)
      end
    end

    def key(name, env)
      variable = KEY_VARIABLES.fetch(name)
      env[variable].presence&.strip.presence || raise(ConfigError, "#{variable} is required for the #{name} provider")
    end
  end
end
