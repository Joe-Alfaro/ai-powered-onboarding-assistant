require "rails_helper"

# R21: the provider and model come from environment variables, with no code change, and a missing
# key gives a clear configuration error or skip instead of a crash.
RSpec.describe Llm::Providers do
  let(:payload) { build_llm_payload }

  describe "R21: LLM_PROVIDER and LLM_MODEL select the provider with no code change" do
    {
      "anthropic" => { "x-api-key" => "test-claude-key" },
      "groq" => { "Authorization" => "Bearer test-groq-key" },
      "gemini" => { "Authorization" => "Bearer test-gemini-key" },
      "ollama" => { "Content-Type" => %r{application/json} }
    }.each do |provider, auth_headers|
      it "LLM_PROVIDER=#{provider} sends the request to #{provider} with LLM_MODEL and its key" do
        stub_provider_success(provider)

        response = Llm::Client.from_env(llm_env("LLM_PROVIDER" => provider, "LLM_MODEL" => "chosen-model"))
          .complete(payload)

        expect(response.provider).to eq(provider)
        expect(response.model).to eq("chosen-model")
        expect(a_request(:post, LlmHelpers::PROVIDER_URLS.fetch(provider)).with(headers: auth_headers) { |request|
          json_body(request)["model"] == "chosen-model"
        }).to have_been_made.once
      end
    end

    it "reads the Ollama endpoint from OLLAMA_BASE_URL" do
      stub_request(:post, "http://ollama.internal:11434/v1/chat/completions")
        .to_return(status: 200, body: openai_body, headers: { "Content-Type" => "application/json" })

      Llm::Client.from_env("LLM_PROVIDER" => "ollama", "LLM_MODEL" => "llama-test",
                           "OLLAMA_BASE_URL" => "http://ollama.internal:11434").complete(payload)

      expect(a_request(:post, "http://ollama.internal:11434/v1/chat/completions")).to have_been_made.once
    end

    it "uses a default model for the provider when LLM_MODEL is unset" do
      stub_provider_success("groq")

      Llm::Client.from_env(llm_env("LLM_PROVIDER" => "groq")).complete(payload)

      expect(a_request(:post, LlmHelpers::GROQ_URL).with { |request|
        model = json_body(request)["model"]
        model.is_a?(String) && model.present?
      }).to have_been_made.once
    end

    it "builds a client without contacting any provider" do
      Llm::Client.from_env(llm_env("LLM_PROVIDER" => "groq", "LLM_FALLBACK_PROVIDER" => "anthropic"))

      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  describe "R21: a missing key gives a clear configuration error, not a crash" do
    {
      "anthropic" => "CLAUDE_API_KEY",
      "groq" => "GROQ_API_KEY",
      "gemini" => "GEMINI_API_KEY"
    }.each do |provider, key|
      it "LLM_PROVIDER=#{provider} without #{key} raises Llm::ConfigError naming #{key}" do
        env = llm_env("LLM_PROVIDER" => provider).except(key)

        expect { Llm::Client.from_env(env) }.to raise_error(Llm::ConfigError, /#{key}/)
      end

      it "LLM_PROVIDER=#{provider} with a blank #{key} is treated as missing" do
        env = llm_env("LLM_PROVIDER" => provider, key => "  ")

        expect { Llm::Client.from_env(env) }.to raise_error(Llm::ConfigError, /#{key}/)
      end
    end

    it "an LLM_FALLBACK_PROVIDER without its key raises Llm::ConfigError naming the key" do
      env = llm_env("LLM_PROVIDER" => "groq", "LLM_FALLBACK_PROVIDER" => "anthropic").except("CLAUDE_API_KEY")

      expect { Llm::Client.from_env(env) }.to raise_error(Llm::ConfigError, /CLAUDE_API_KEY/)
    end

    it "an unset LLM_PROVIDER raises Llm::ConfigError naming LLM_PROVIDER" do
      expect { Llm::Client.from_env(llm_env) }.to raise_error(Llm::ConfigError, /LLM_PROVIDER/)
    end

    it "an unknown LLM_PROVIDER raises Llm::ConfigError listing the supported providers" do
      expect { Llm::Client.from_env(llm_env("LLM_PROVIDER" => "openai-paid")) }
        .to raise_error(Llm::ConfigError, /anthropic.*groq.*gemini.*ollama/m)
    end

    it "an unknown LLM_FALLBACK_PROVIDER raises Llm::ConfigError" do
      expect { Llm::Client.from_env(llm_env("LLM_PROVIDER" => "groq", "LLM_FALLBACK_PROVIDER" => "nope")) }
        .to raise_error(Llm::ConfigError, /LLM_FALLBACK_PROVIDER/)
    end

    it "Ollama needs no key" do
      expect { Llm::Client.from_env("LLM_PROVIDER" => "ollama") }.not_to raise_error
    end

    it "never puts a key value in a configuration error message" do
      env = llm_env("LLM_PROVIDER" => "groq", "LLM_FALLBACK_PROVIDER" => "anthropic").except("CLAUDE_API_KEY")

      expect { Llm::Client.from_env(env) }.to raise_error(Llm::ConfigError) { |error|
        expect(error.message).not_to include(*LlmHelpers::TEST_KEYS.values)
      }
    end
  end

  describe "R21: callers such as the eval harness can skip providers with no key" do
    it "lists the supported providers" do
      expect(described_class::NAMES).to eq(%w[anthropic groq gemini ollama])
    end

    it "reports only the providers whose credentials are set" do
      expect(described_class.configured("GROQ_API_KEY" => "test-groq-key")).to eq(%w[groq])
    end

    it "counts Ollama as configured when OLLAMA_BASE_URL is set" do
      env = { "OLLAMA_BASE_URL" => "http://localhost:11434", "GEMINI_API_KEY" => "test-gemini-key" }

      expect(described_class.configured(env)).to eq(%w[gemini ollama])
    end

    it "reports none, without raising, when no credentials are set" do
      expect(described_class.configured({})).to eq([])
    end

    it "treats blank keys as missing" do
      expect(described_class.configured("CLAUDE_API_KEY" => "", "GROQ_API_KEY" => " ")).to eq([])
    end
  end
end
