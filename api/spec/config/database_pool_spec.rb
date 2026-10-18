require "rails_helper"

# R22: chat requests spend most of their time waiting on the LLM without a database connection,
# so Puma can run more threads than the database allows connections. DB_POOL caps the pool apart
# from RAILS_MAX_THREADS, inside the hosted database's connection limit.
RSpec.describe "Database connection pool size" do
  def pool_size(env)
    stub_const("ENV", env)
    ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/database.yml"))
                                    .dig("production", "max_connections")
  end

  it "R22: uses DB_POOL when it is set, whatever the thread count" do
    expect(pool_size("RAILS_MAX_THREADS" => "24", "DB_POOL" => "8")).to eq(8)
  end

  it "R22: matches RAILS_MAX_THREADS up to 10 when DB_POOL is unset" do
    expect(pool_size("RAILS_MAX_THREADS" => "3")).to eq(3)
    expect(pool_size("RAILS_MAX_THREADS" => "24")).to eq(10)
  end

  it "R22: defaults to 5 with neither set" do
    expect(pool_size({})).to eq(5)
  end
end
