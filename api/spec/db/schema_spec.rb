require "rails_helper"
require "open3"

# R32: schema changes are committed migrations. The committed db/schema.rb must be exactly what
# the migrations produce, and the test database must have no pending migrations.
RSpec.describe "db/schema.rb" do
  it "has no pending migrations" do
    expect(ActiveRecord::Base.connection_pool.migration_context.needs_migration?).to be(false)
    expect { ActiveRecord::Migration.check_all_pending! }.not_to raise_error
  end

  it "has a migration file for the schema version" do
    version = Rails.root.join("db/schema.rb").read[/define\(version: ([\d_]+)\)/, 1].delete("_")

    expect(Rails.root.glob("db/migrate/#{version}_*.rb")).not_to be_empty
  end

  # Migrates a scratch database from nothing in a separate process and compares its dump with the
  # committed file, so a hand-edited schema.rb or a migration missing from the commit fails here.
  it "matches what the migrations produce on an empty database" do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    scratch = "api_schema_check_#{Process.pid}"
    url = "postgres://#{config[:username]}:#{config[:password]}@#{config[:host]}:#{config[:port]}/#{scratch}"

    Dir.mktmpdir do |dir|
      dumped = File.join(dir, "schema.rb")
      env = { "RAILS_ENV" => "test", "DATABASE_URL" => url, "SCHEMA" => dumped }
      begin
        _output, status = Open3.capture2e(env, "bin/rails", "db:create", "db:migrate", chdir: Rails.root.to_s)
        expect(status).to be_success, "migrating a scratch database failed"

        expect(File.read(dumped)).to eq(Rails.root.join("db/schema.rb").read)
      ensure
        Open3.capture2e(env, "bin/rails", "db:drop", chdir: Rails.root.to_s)
      end
    end
  end
end
