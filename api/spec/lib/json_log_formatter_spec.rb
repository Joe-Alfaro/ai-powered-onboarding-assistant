require "rails_helper"

RSpec.describe JsonLogFormatter do
  subject(:formatter) { described_class.new }

  def entry(message)
    JSON.parse(formatter.call("INFO", Time.utc(2026, 10, 15), nil, message))
  end

  it "merges a JSON object message into the entry" do
    expect(entry('{"status":200}')).to include("level" => "INFO", "status" => 200)
  end

  it "wraps plain text as the message" do
    expect(entry("plain text")).to include("message" => "plain text")
  end

  it "wraps text that only looks like JSON as the message" do
    expect(entry("{not json")).to include("message" => "{not json")
  end

  it "logs an exception's class but not its message" do
    expect(entry(RuntimeError.new("secret detail")).to_s).not_to include("secret detail")
  end

  it "merges a hash message" do
    expect(entry({ event: "x" })).to include("event" => "x")
  end
end
