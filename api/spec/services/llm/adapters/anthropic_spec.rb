require "rails_helper"

RSpec.describe Llm::Adapters::Anthropic do
  subject(:adapter) { described_class.new(api_key: "test-claude-key", model: "claude-test-model") }

  let(:provider_url) { LlmHelpers::ANTHROPIC_URL }
  let(:payload) do
    build_llm_payload(turns: [
      { role: "user", content: "I need an appointment." },
      { role: "assistant", content: "Sure. What brings you in?" },
      { role: "user", content: "Mostly stress at work." }
    ])
  end

  it_behaves_like "an LLM adapter that maps provider failures to typed errors"

  describe "structured output through tool use" do
    before { stub_provider_success("anthropic") }

    it "sends one tool whose input schema is the payload's response schema, and forces that tool" do
      adapter.complete(payload, timeout: 6)

      expect(a_request(:post, provider_url).with { |request|
        body = json_body(request)
        tool = body.fetch("tools").sole
        tool["input_schema"] == LlmHelpers::RESPONSE_SCHEMA &&
          body["tool_choice"] == { "type" => "tool", "name" => tool["name"] }
      }).to have_been_made.once
    end

    it "sends the model, the system prompt, the turns and a max_tokens limit" do
      adapter.complete(payload, timeout: 6)

      expect(a_request(:post, provider_url).with { |request|
        body = json_body(request)
        body["model"] == "claude-test-model" &&
          body["system"] == payload.system &&
          body["messages"] == payload.messages.map(&:deep_stringify_keys) &&
          body["max_tokens"].is_a?(Integer) && body["max_tokens"].positive?
      }).to have_been_made.once
    end

    it "authenticates with x-api-key and pins an anthropic-version" do
      adapter.complete(payload, timeout: 6)

      expect(a_request(:post, provider_url).with(headers: {
        "x-api-key" => "test-claude-key",
        "anthropic-version" => /\A\d{4}-\d{2}-\d{2}\z/,
        "Content-Type" => %r{application/json}
      })).to have_been_made.once
    end

    it "returns the tool input as the response data, with provider and model" do
      response = adapter.complete(payload, timeout: 6)

      expect(response).to be_a(Llm::Response)
      expect(response.data).to eq(LlmHelpers::STRUCTURED_REPLY)
      expect(response.provider).to eq("anthropic")
      expect(response.model).to eq("claude-test-model")
    end
  end

  it "R16 no unhandled error: a reply with no tool_use block raises Llm::InvalidResponseError" do
    body = { type: "message", role: "assistant", content: [ { type: "text", text: "Hello!" } ] }.to_json
    stub_request(:post, provider_url).to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::InvalidResponseError)
  end

  it "R16 client timeout: gives up on a provider that never answers, within the timeout it was given" do
    HangingServer.open do |server|
      hung = described_class.new(api_key: "test-claude-key", model: "claude-test-model", base_url: server.url)

      elapsed = elapsed_seconds do
        expect { hung.complete(payload, timeout: 0.5) }.to raise_error(Llm::TimeoutError)
      end

      expect(elapsed).to be < 2
    end
  end
end
