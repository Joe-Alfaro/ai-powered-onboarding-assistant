require "rails_helper"

# R31: GET /health reports app, database, storage, OCR and LLM status.
RSpec.describe "GET /health", type: :request do
  let(:llm_calls) { [] }
  let(:storage_calls) { [] }
  let(:llm) { Health::CachedProbe.new(-> { llm_calls << 1; true }, ttl: 5.minutes) }
  let(:storage) { Health::CachedProbe.new(-> { storage_calls << 1; true }, ttl: 5.minutes) }
  let(:ocr) { -> { true } }
  let(:database) { Health::Probes::Database.new }
  let(:probes) { { database: database, storage: storage, ocr: ocr, llm: llm } }

  before { allow(Health::Check).to receive(:probes).and_return(probes) }

  def statuses
    response.parsed_body.fetch("checks").transform_values { |check| check.fetch("status") }
  end

  it "R31: reports every dependency as ok, without a token" do
    get "/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["status"]).to eq("ok")
    expect(statuses).to eq("app" => "ok", "database" => "ok", "storage" => "ok", "ocr" => "ok", "llm" => "ok")
  end

  {
    storage: "storage",
    ocr: "ocr",
    llm: "llm"
  }.each do |name, key|
    it "R31: breaking #{name} changes only its status and keeps a 200" do
      probes[name] = -> { raise Errno::ECONNREFUSED }

      get "/health"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("degraded")
      expected = { "app" => "ok", "database" => "ok", "storage" => "ok", "ocr" => "ok", "llm" => "ok" }
      expect(statuses).to eq(expected.merge(key => "down"))
    end
  end

  context "when the database is unreachable" do
    let(:database) { Health::Probes::Database.new(unreachable_database) }

    it "R31: reports the database as down, changes nothing else, and returns 503" do
      get "/health"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["status"]).to eq("down")
      expect(statuses).to eq("app" => "ok", "database" => "down", "storage" => "ok", "ocr" => "ok", "llm" => "ok")
    end
  end

  it "R31: repeated pings call the LLM provider once within the cache window" do
    5.times { get "/health" }

    expect(llm_calls.size).to eq(1)
  end

  it "R31: repeated pings call storage once within the cache window" do
    5.times { get "/health" }

    expect(storage_calls.size).to eq(1)
  end

  it "doesn't expose a failing probe's error message" do
    probes[:llm] = -> { raise "provider said: key sk-spec-123 is invalid" }

    get "/health"

    expect(response.body).not_to include("sk-spec-123")
  end
end
