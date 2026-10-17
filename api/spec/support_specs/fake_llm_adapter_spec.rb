require "rails_helper"

RSpec.describe FakeLlmAdapter do
  let(:payload) { build_llm_payload }

  it "returns scripted responses in order and counts calls" do
    adapter = described_class.new(provider: "groq", model: "m")
      .respond_with(intent: "ask-question", assessment_fields: {}, reply: "first")
      .respond_with(intent: "out-of-scope", assessment_fields: {}, reply: "second")

    replies = 2.times.map { adapter.complete(payload, timeout: 6).data["reply"] }

    expect(replies).to eq(%w[first second])
    expect(adapter.call_count).to eq(2)
    expect(adapter.payloads).to all(be(payload))
  end

  it "raises scripted errors" do
    adapter = described_class.new.fail_with(Llm::RateLimitError)

    expect { adapter.complete(payload, timeout: 6) }.to raise_error(Llm::RateLimitError)
  end

  it "simulates a hang by waiting out the timeout it was given, then raising a timeout" do
    adapter = described_class.new.hang

    elapsed = elapsed_seconds do
      expect { adapter.complete(payload, timeout: 0.2) }.to raise_error(Llm::TimeoutError)
    end

    expect(elapsed).to be >= 0.2
    expect(adapter.timeouts).to eq([ 0.2 ])
  end

  it "answers after the scripted delay when it is shorter than the timeout" do
    adapter = described_class.new.respond_after(0.2, LlmHelpers::STRUCTURED_REPLY)

    response = nil
    elapsed = elapsed_seconds { response = adapter.complete(payload, timeout: 1) }

    expect(elapsed).to be >= 0.2
    expect(response.data).to eq(LlmHelpers::STRUCTURED_REPLY.deep_stringify_keys)
  end

  it "times out instead of answering when the scripted delay is longer than the timeout" do
    adapter = described_class.new.respond_after(5, LlmHelpers::STRUCTURED_REPLY)

    elapsed = elapsed_seconds do
      expect { adapter.complete(payload, timeout: 0.2) }.to raise_error(Llm::TimeoutError)
    end

    expect(elapsed).to be_between(0.2, 1)
  end

  it "falls back to the default response once the queue is empty" do
    adapter = described_class.new.always_respond_with(LlmHelpers::STRUCTURED_REPLY)

    3.times { adapter.complete(payload, timeout: 6) }

    expect(adapter.call_count).to eq(3)
  end

  it "fails loudly when the script runs out" do
    expect { described_class.new.complete(payload, timeout: 6) }.to raise_error(/no scripted step/)
  end
end
