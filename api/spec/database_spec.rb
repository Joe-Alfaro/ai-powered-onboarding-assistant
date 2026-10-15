require "rails_helper"

RSpec.describe "Test database" do
  it "runs queries against a real Postgres" do
    version = ActiveRecord::Base.connection.select_value("SHOW server_version")

    expect(version).to match(/\A\d+/)
  end
end
