require "rails_helper"

RSpec.describe Llm::Adapters::OpenAiCompatible do
  subject(:adapter) do
    described_class.new(provider: "groq", base_url: "https://api.groq.com/openai/v1",
                        api_key: "test-groq-key", model: "groq-test-model")
  end

  let(:provider_url) { LlmHelpers::GROQ_URL }
  let(:payload) do
    build_llm_payload(turns: [
      { role: "user", content: "I need an appointment." },
      { role: "assistant", content: "Sure. What brings you in?" },
      { role: "user", content: "Mostly stress at work." }
    ])
  end

  it_behaves_like "an LLM adapter that maps provider failures to typed errors"

  describe "structured output through a JSON-schema response format" do
    before { stub_provider_success("groq") }

    it "asks for a json_schema response format carrying the payload's response schema" do
      adapter.complete(payload, timeout: 6)

      expect(a_request(:post, provider_url).with { |request|
        format = json_body(request).fetch("response_format")
        format["type"] == "json_schema" &&
          format.dig("json_schema", "schema") == LlmHelpers::RESPONSE_SCHEMA &&
          format.dig("json_schema", "name").is_a?(String)
      }).to have_been_made.once
    end

    it "sends the model, then the system prompt as the first message followed by the turns" do
      adapter.complete(payload, timeout: 6)

      expected_messages = [ { "role" => "system", "content" => payload.system } ] +
        payload.messages.map(&:deep_stringify_keys)
      expect(a_request(:post, provider_url).with { |request|
        body = json_body(request)
        body["model"] == "groq-test-model" && body["messages"] == expected_messages
      }).to have_been_made.once
    end

    it "authenticates with a bearer token" do
      adapter.complete(payload, timeout: 6)

      expect(a_request(:post, provider_url).with(headers: { "Authorization" => "Bearer test-groq-key" }))
        .to have_been_made.once
    end

    it "returns the parsed JSON content as the response data, with provider and model" do
      response = adapter.complete(payload, timeout: 6)

      expect(response).to be_a(Llm::Response)
      expect(response.data).to eq(LlmHelpers::STRUCTURED_REPLY)
      expect(response.provider).to eq("groq")
      expect(response.model).to eq("groq-test-model")
    end
  end

  it "sends no Authorization header when the provider needs no key (Ollama)" do
    ollama = described_class.new(provider: "ollama", base_url: "http://localhost:11434/v1", api_key: nil, model: "llama-test")
    stub_provider_success("ollama")

    ollama.complete(payload, timeout: 6)

    expect(a_request(:post, LlmHelpers::OLLAMA_URL).with { |request| !request.headers.key?("Authorization") })
      .to have_been_made.once
  end

  it "R16 no unhandled error: message content that is not JSON raises Llm::InvalidResponseError" do
    stub_request(:post, provider_url).to_return(status: 200, body: openai_body("Sure, here you go!"),
                                                headers: { "Content-Type" => "application/json" })

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::InvalidResponseError)
  end

  it "R16 no unhandled error: a reply with no choices raises Llm::InvalidResponseError" do
    stub_request(:post, provider_url).to_return(status: 200, body: { choices: [] }.to_json,
                                                headers: { "Content-Type" => "application/json" })

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::InvalidResponseError)
  end

  it "R16 client timeout: gives up on a provider that never answers, within the timeout it was given" do
    HangingServer.open do |server|
      hung = described_class.new(provider: "ollama", base_url: "#{server.url}/v1", api_key: nil, model: "llama-test")

      elapsed = elapsed_seconds do
        expect { hung.complete(payload, timeout: 0.5) }.to raise_error(Llm::TimeoutError)
      end

      expect(elapsed).to be < 2
    end
  end
end
