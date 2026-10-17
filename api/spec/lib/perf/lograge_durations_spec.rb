require "rails_helper"

# R24 check 1 logs each request's server time on its Lograge line; the timing tasks read it back.
RSpec.describe Perf::LogrageDurations do
  def line(fields)
    JSON.generate({ level: "INFO", time: "2026-10-17T10:00:00.000Z" }.merge(fields))
  end

  it "returns the duration of each requested request ID, in the order asked" do
    log = [
      line(method: "POST", path: "/bookings", status: 201, duration: 12.5, request_id: "a"),
      "Started GET /slots for 127.0.0.1",
      line(method: "POST", path: "/bookings", status: 201, duration: 30.25, request_id: "b"),
      line(method: "GET", path: "/slots", status: 200, duration: 4.0, request_id: "c")
    ].join("\n")

    expect(described_class.new(log).for_request_ids(%w[b a])).to eq("b" => 30.25, "a" => 12.5)
  end

  it "reads lines that a log tag or timestamp prefixes" do
    log = "[abc] " + line(duration: 7.5, request_id: "x")
    expect(described_class.new(log).for_request_ids(%w[x])).to eq("x" => 7.5)
  end

  it "leaves out request IDs that have no Lograge line, and lines without a duration" do
    log = [ line(request_id: "y", message: "no duration"), "{not json" ].join("\n")
    expect(described_class.new(log).for_request_ids(%w[y z])).to eq({})
  end
end
