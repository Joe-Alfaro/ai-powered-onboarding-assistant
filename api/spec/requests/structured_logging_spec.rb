require "rails_helper"

module StructuredLoggingSpec
  PERSONAL = {
    full_name: "Octavia Brimblecombe-Xylo",
    date_of_birth: "1961-11-23",
    address: "742 Quillfeather Lane",
    message: "my name is Octavia Brimblecombe-Xylo"
  }.freeze

  class EchoController < ApplicationController
    def show
      render json: { ok: true }
    end

    def create
      head :no_content
    end

    def explode
      raise "failed for #{PERSONAL[:full_name]} at #{PERSONAL[:address]}"
    end
  end
end

# R31: logs are single-line JSON with no personal data.
RSpec.describe "Structured logs", type: :request do
  let(:headers) { auth_headers(SecureRandom.uuid) }

  before do
    draw_spec_routes do
      get "/spec/echo", to: "structured_logging_spec/echo#show"
      post "/spec/echo", to: "structured_logging_spec/echo#create"
      get "/spec/explode", to: "structured_logging_spec/echo#explode"
    end
  end

  def parsed(lines)
    lines.map { |line| JSON.parse(line) }
  end

  it "R31: logs a request as one JSON line with method, path, status and duration" do
    lines = log_lines(capture_logs { get "/spec/echo", headers: headers })

    expect(lines.size).to eq(1)
    entry = JSON.parse(lines.first)
    expect(entry).to include("method" => "GET", "path" => "/spec/echo", "status" => 200)
    expect(entry).to have_key("duration")
  end

  it "R31: every line logged for a request is a JSON object" do
    lines = log_lines(capture_logs { post "/spec/echo", params: StructuredLoggingSpec::PERSONAL, headers: headers })

    expect(lines).not_to be_empty
    expect(parsed(lines)).to all(be_a(Hash))
  end

  it "R31: logs an error as structured JSON naming the error class" do
    lines = log_lines(capture_logs { get "/spec/explode", headers: headers })

    expect(parsed(lines)).to all(be_a(Hash))
    expect(lines.join).to include("RuntimeError")
  end

  it "R31: keeps personal data out of the error log, including the exception message" do
    output = capture_logs { get "/spec/explode", headers: headers }

    expect(output).not_to include("Brimblecombe")
    expect(output).not_to include("Quillfeather")
  end

  it "R15: keeps posted personal-data params out of the logs" do
    output = capture_logs { post "/spec/echo", params: StructuredLoggingSpec::PERSONAL, headers: headers }

    StructuredLoggingSpec::PERSONAL.each_value { |value| expect(output).not_to include(value) }
  end

  it "keeps the bearer token out of the logs" do
    output = capture_logs { post "/spec/echo", headers: headers }

    expect(output).not_to include(headers["Authorization"].split.last)
  end
end
