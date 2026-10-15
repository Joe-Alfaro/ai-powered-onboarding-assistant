require "rails_helper"

# R31: the LLM and storage checks are cached probes that don't call the provider on every ping.
RSpec.describe Health::CachedProbe do
  let(:calls) { [] }
  let(:result) { true }
  let(:probe) { -> { calls << Time.current; result } }

  subject(:cached) { described_class.new(probe, ttl: 5.minutes) }

  it "exposes its ttl" do
    expect(cached.ttl).to eq(5.minutes)
  end

  it "R31: calls the underlying probe once for repeated pings within the ttl" do
    5.times { cached.call }

    expect(calls.size).to eq(1)
  end

  it "returns the underlying probe's result" do
    expect(cached.call).to be(true)
  end

  it "calls the underlying probe again once the ttl has passed" do
    cached.call
    travel(5.minutes + 1.second) { cached.call }

    expect(calls.size).to eq(2)
  end

  it "R31: reports a dependency that broke as down once the ttl has passed" do
    states = [ true, false ]
    cached = described_class.new(-> { states.shift }, ttl: 5.minutes)

    expect(cached.call).to be(true)
    travel(5.minutes + 1.second) { expect(cached.call).to be(false) }
  end

  it "reports a probe that raises as down instead of raising" do
    cached = described_class.new(-> { raise Errno::ECONNREFUSED }, ttl: 5.minutes)

    expect(cached.call).to be(false)
  end
end
