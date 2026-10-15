# R16: every adapter turns provider failures into typed errors the caller can offer as
# "try again" or "continue manually". Host groups define `adapter` and `provider_url`.
RSpec.shared_examples "an LLM adapter that maps provider failures to typed errors" do
  let(:payload) { build_llm_payload }

  def expect_typed_error(error_class, code)
    expect { adapter.complete(payload, timeout: 6) }.to raise_error(error_class) { |error|
      expect(error).to be_a(Llm::Error)
      expect(error.code).to eq(code)
      expect(error.actions).to eq(%w[try_again continue_manually])
      expect(error.message).to be_present
      expect(error.message).not_to include(*LlmHelpers::TEST_KEYS.values)
    }
    expect(a_request(:post, provider_url)).to have_been_made.once
  end

  it "R16 timeout: a provider timeout raises Llm::TimeoutError after one request" do
    stub_request(:post, provider_url).to_timeout

    expect_typed_error(Llm::TimeoutError, "llm_timeout")
  end

  [ 500, 502, 503 ].each do |status|
    it "R16 5xx: a #{status} raises Llm::ServerError after one request" do
      stub_request(:post, provider_url).to_return(status: status, body: "upstream error")

      expect_typed_error(Llm::ServerError, "llm_server_error")
    end
  end

  it "R16 429: a rate limit raises Llm::RateLimitError after one request" do
    stub_request(:post, provider_url).to_return(status: 429, body: { error: "rate limited" }.to_json)

    expect_typed_error(Llm::RateLimitError, "llm_rate_limited")
  end

  [ Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError ].each do |failure|
    it "R16 connection failure: #{failure} raises Llm::ConnectionError after one request" do
      stub_request(:post, provider_url).to_raise(failure)

      expect_typed_error(Llm::ConnectionError, "llm_unreachable")
    end
  end

  it "R16 no unhandled error: any other HTTP error status raises an Llm::Error" do
    stub_request(:post, provider_url).to_return(status: 400, body: "bad request")

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::Error) { |error|
      expect(error.actions).to eq(%w[try_again continue_manually])
    }
  end

  it "R16 no unhandled error: a 200 whose body is not JSON raises Llm::InvalidResponseError" do
    stub_request(:post, provider_url).to_return(status: 200, body: "<html>gateway</html>")

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::InvalidResponseError) { |error|
      expect(error).to be_a(Llm::Error)
      expect(error.actions).to eq(%w[try_again continue_manually])
    }
  end

  it "R20 single exit: refuses anything that is not an Llm::Payload, without sending a request" do
    stub_request(:post, provider_url)

    expect { adapter.complete({ system: "x", messages: [] }, timeout: 6) }.to raise_error(ArgumentError)
    expect(a_request(:post, provider_url)).not_to have_been_made
  end
end
