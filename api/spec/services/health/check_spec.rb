require "rails_helper"

# R31: the health check reports app, database, storage, OCR and LLM status, and breaking any one
# dependency changes only that dependency's status.
RSpec.describe Health::Check do
  let(:healthy) { -> { true } }
  let(:probes) { { database: healthy, storage: healthy, ocr: healthy, llm: healthy } }

  def statuses(result)
    result.fetch(:checks).transform_values { |check| check.fetch(:status) }
  end

  it "R31: reports app, database, storage, OCR and LLM as ok when all are healthy" do
    result = described_class.new(probes: probes).call

    expect(result[:status]).to eq("ok")
    expect(statuses(result)).to eq(app: "ok", database: "ok", storage: "ok", ocr: "ok", llm: "ok")
  end

  %i[database storage ocr llm].each do |name|
    it "R31: breaking #{name} (probe returns false) changes only the #{name} status" do
      result = described_class.new(probes: probes.merge(name => -> { false })).call

      expected = { app: "ok", database: "ok", storage: "ok", ocr: "ok", llm: "ok" }.merge(name => "down")
      expect(statuses(result)).to eq(expected)
    end

    it "R31: breaking #{name} (probe raises) changes only the #{name} status" do
      result = described_class.new(probes: probes.merge(name => -> { raise "boom" })).call

      expected = { app: "ok", database: "ok", storage: "ok", ocr: "ok", llm: "ok" }.merge(name => "down")
      expect(statuses(result)).to eq(expected)
    end
  end

  it "reports the overall status as down when the database is down" do
    result = described_class.new(probes: probes.merge(database: -> { false })).call

    expect(result[:status]).to eq("down")
  end

  it "reports the overall status as degraded when only a non-database dependency is down" do
    result = described_class.new(probes: probes.merge(llm: -> { false })).call

    expect(result[:status]).to eq("degraded")
  end

  describe ".probes (the app's registered probes)" do
    it "registers a probe for the database, storage, OCR and LLM" do
      expect(described_class.probes.keys).to contain_exactly(:database, :storage, :ocr, :llm)
    end

    it "checks the database on every call, so each ping touches Postgres" do
      expect(described_class.probes[:database]).not_to be_a(Health::CachedProbe)
    end

    %i[storage ocr llm].each do |name|
      it "R31: caches the #{name} probe for at most 5 minutes so pings don't call the provider each time" do
        probe = described_class.probes[name]

        expect(probe).to be_a(Health::CachedProbe)
        expect(probe.ttl).to be <= 5.minutes
      end
    end
  end
end
