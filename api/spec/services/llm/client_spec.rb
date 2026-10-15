require "rails_helper"

RSpec.describe Llm::Client do
  let(:payload) { build_llm_payload }

  describe "R16: every LLM call has a client timeout" do
    it "uses a 6 second client timeout" do
      expect(described_class::TIMEOUT_SECONDS).to eq(6)
    end

    it "gives the provider adapter a timeout of at most 6 s on every call" do
      primary = FakeLlmAdapter.new.respond_with(LlmHelpers::STRUCTURED_REPLY)

      described_class.new(primary: primary).complete(payload)

      expect(primary.timeouts.sole).to be_between(0.1, 6)
    end

    it "fails within 10 s even when the primary and the fallback both hang" do
      primary = FakeLlmAdapter.new(provider: "groq").hang
      fallback = FakeLlmAdapter.new(provider: "anthropic").hang
      client = described_class.new(primary: primary, fallback: fallback)

      elapsed = elapsed_seconds do
        expect { client.complete(payload) }.to raise_error(Llm::TimeoutError) { |error|
          expect(error.actions).to eq(%w[try_again continue_manually])
        }
      end

      expect(elapsed).to be < 10
      expect(primary.timeouts.sole).to be <= 6
      expect(fallback.call_count).to be <= 1
    end

    it "fails with a timeout error within 10 s when a real provider accepts the connection and never answers" do
      HangingServer.open do |server|
        client = described_class.from_env("LLM_PROVIDER" => "ollama", "LLM_MODEL" => "llama-test",
                                          "OLLAMA_BASE_URL" => server.url)

        elapsed = elapsed_seconds do
          expect { client.complete(payload) }.to raise_error(Llm::TimeoutError) { |error|
            expect(error.actions).to eq(%w[try_again continue_manually])
          }
        end

        expect(elapsed).to be < 10
      end
    end
  end

  describe "R16: provider failures become typed errors offering try again and continue manually" do
    let(:client) { described_class.from_env(llm_env("LLM_PROVIDER" => "groq", "LLM_MODEL" => "groq-test-model")) }

    {
      "timeout" => [ ->(stub) { stub.to_timeout }, Llm::TimeoutError ],
      "5xx" => [ ->(stub) { stub.to_return(status: 503) }, Llm::ServerError ],
      "429" => [ ->(stub) { stub.to_return(status: 429) }, Llm::RateLimitError ],
      "connection failure" => [ ->(stub) { stub.to_raise(Errno::ECONNREFUSED) }, Llm::ConnectionError ]
    }.each do |failure, (respond, error_class)|
      it "R16 #{failure}: raises #{error_class} with both actions after exactly one request" do
        respond.call(stub_request(:post, LlmHelpers::GROQ_URL))

        expect { client.complete(payload) }.to raise_error(error_class) { |error|
          expect(error.actions).to eq(%w[try_again continue_manually])
        }
        expect(a_request(:post, LlmHelpers::GROQ_URL)).to have_been_made.once
      end
    end

    it "returns the structured response when the provider answers" do
      stub_provider_success("groq")

      response = client.complete(payload)

      expect(response.data).to eq(LlmHelpers::STRUCTURED_REPLY)
      expect(response.provider).to eq("groq")
    end
  end

  describe "R16: LLM_FALLBACK_PROVIDER is tried once on a timeout, 5xx or 429" do
    let(:env) do
      llm_env("LLM_PROVIDER" => "groq", "LLM_MODEL" => "groq-test-model",
              "LLM_FALLBACK_PROVIDER" => "anthropic", "LLM_FALLBACK_MODEL" => "claude-fallback-model")
    end
    let(:client) { described_class.from_env(env) }

    {
      "timeout" => ->(stub) { stub.to_timeout },
      "5xx" => ->(stub) { stub.to_return(status: 502) },
      "429" => ->(stub) { stub.to_return(status: 429) }
    }.each do |failure, respond|
      it "R16 fallback on #{failure}: answers from the fallback provider after one request to each" do
        respond.call(stub_request(:post, LlmHelpers::GROQ_URL))
        stub_provider_success("anthropic")

        response = client.complete(payload)

        expect(response.data).to eq(LlmHelpers::STRUCTURED_REPLY)
        expect(response.provider).to eq("anthropic")
        expect(a_request(:post, LlmHelpers::GROQ_URL)).to have_been_made.once
        expect(a_request(:post, LlmHelpers::ANTHROPIC_URL)).to have_been_made.once
      end
    end

    it "sends the fallback request with LLM_FALLBACK_MODEL" do
      stub_provider_status("groq", 503)
      stub_provider_success("anthropic")

      client.complete(payload)

      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL).with { |request|
        json_body(request)["model"] == "claude-fallback-model"
      }).to have_been_made.once
    end

    it "uses the fallback provider's default model when LLM_FALLBACK_MODEL is unset" do
      stub_provider_status("groq", 503)
      stub_provider_success("anthropic")

      described_class.from_env(env.except("LLM_FALLBACK_MODEL")).complete(payload)

      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL).with { |request|
        model = json_body(request)["model"]
        model.is_a?(String) && model.present? && model != "groq-test-model"
      }).to have_been_made.once
    end

    it "raises a typed error, without retrying either provider, when the fallback also fails" do
      stub_provider_status("groq", 503)
      stub_provider_status("anthropic", 429)

      expect { client.complete(payload) }.to raise_error(Llm::Error) { |error|
        expect(error.actions).to eq(%w[try_again continue_manually])
      }
      expect(a_request(:post, LlmHelpers::GROQ_URL)).to have_been_made.once
      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL)).to have_been_made.once
    end

    it "does not use the fallback for a request the provider rejected as invalid (4xx other than 429)" do
      stub_provider_status("groq", 400)
      stub_provider_success("anthropic")

      expect { client.complete(payload) }.to raise_error(Llm::Error)
      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL)).not_to have_been_made
    end

    it "does not use the fallback for malformed structured output (the chat layer retries that)" do
      stub_request(:post, LlmHelpers::GROQ_URL).to_return(status: 200, body: openai_body("not json"))
      stub_provider_success("anthropic")

      expect { client.complete(payload) }.to raise_error(Llm::InvalidResponseError)
      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL)).not_to have_been_made
    end

    it "with no fallback configured, raises the primary's error after one request" do
      stub_provider_status("groq", 503)

      expect { described_class.from_env(env.except("LLM_FALLBACK_PROVIDER")).complete(payload) }
        .to raise_error(Llm::ServerError)
      expect(a_request(:post, LlmHelpers::GROQ_URL)).to have_been_made.once
    end
  end

  describe "with injected adapters (the seam the chat slice uses)" do
    it "tries the fallback adapter once when the primary is rate limited" do
      primary = FakeLlmAdapter.new(provider: "groq").fail_with(Llm::RateLimitError)
      fallback = FakeLlmAdapter.new(provider: "anthropic").respond_with(LlmHelpers::STRUCTURED_REPLY)

      response = described_class.new(primary: primary, fallback: fallback).complete(payload)

      expect(response.provider).to eq("anthropic")
      expect([ primary.call_count, fallback.call_count ]).to eq([ 1, 1 ])
      expect(fallback.payloads.sole).to be(payload)
    end

    it "R20 single exit: refuses anything that is not an Llm::Payload, without calling a provider" do
      primary = FakeLlmAdapter.new.always_respond_with(LlmHelpers::STRUCTURED_REPLY)

      expect { described_class.new(primary: primary).complete({ system: "x", messages: [] }) }
        .to raise_error(ArgumentError)
      expect(primary.call_count).to eq(0)
    end
  end
end
