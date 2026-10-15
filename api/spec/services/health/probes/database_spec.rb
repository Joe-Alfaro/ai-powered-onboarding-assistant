require "rails_helper"

RSpec.describe Health::Probes::Database do
  it "R31: is healthy when Postgres answers" do
    expect(described_class.new.call).to be_truthy
  end

  it "R31: is down when Postgres is unreachable" do
    check = Health::Check.new(probes: { database: described_class.new(unreachable_database) })

    expect(check.call.dig(:checks, :database, :status)).to eq("down")
  end
end
