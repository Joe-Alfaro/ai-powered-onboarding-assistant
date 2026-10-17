require "rails_helper"

# R23, R24: what the timing tasks report from a run's replies and the API's log.
RSpec.describe Perf::TimingReport do
  def reply(status, client_ms, request_id)
    Perf::ApiClient::Reply.new(status: status, body: {}, request_id: request_id, client_ms: client_ms)
  end

  let(:replies) do
    Array.new(19) { |i| reply(201, 100.0 + i, "ok-#{i}") } + [ reply(409, 5.0, "failed") ]
  end
  let(:success) { ->(r) { r.status == 201 } }

  it "counts failures and the error rate, and times only the successful requests" do
    report = described_class.new(name: "Booking", replies: replies, success: success).to_h

    expect(report).to include(runs: 20, failures: 1, error_rate: 0.05, statuses: { 201 => 19, 409 => 1 })
    expect(report[:client_ms]).to include(count: 19, min: 100.0, p95: 118.0, max: 118.0)
    expect(report[:server_ms]).to be_nil
  end

  it "reads the server times of the successful requests from the log, and counts missing lines" do
    log = replies.first(18).map { |r| JSON.generate(request_id: r.request_id, duration: r.client_ms / 10) }
    log << JSON.generate(request_id: "failed", duration: 9_999.0)
    report = described_class.new(name: "Booking", replies: replies, success: success, log_text: log.join("\n")).to_h

    expect(report[:server_ms]).to include(count: 18, min: 10.0, p95: 11.7, max: 11.7, missing_log_lines: 1)
  end

  it "prints one line per measure" do
    lines = described_class.new(name: "Booking", replies: replies, success: success).lines

    expect(lines.first).to eq("Booking: 20 runs, 1 failed (error rate 5.0%), statuses {201 => 19, 409 => 1}")
    expect(lines).to include(a_string_starting_with("  client-side ms: count 19"), "  server-side ms: no PERF_LOG_FILE given")
  end
end
