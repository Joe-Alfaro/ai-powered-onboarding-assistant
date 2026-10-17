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

  # R32: pg_dump-style formatting (check constraints especially) changes between Postgres minor
  # releases, so a floating tag like postgres:17 lets bin/rails db:migrate rewrite schema.rb on a
  # machine that pulled a newer image. Local, CI and this suite must all run one exact version.
  describe "pinned Postgres version" do
    let(:repo_root) { Rails.root.join("..").expand_path }
    let(:compose_image) { YAML.safe_load(repo_root.join("docker-compose.yml").read).dig("services", "postgres", "image") }
    let(:pinned_version) { compose_image[/\Apostgres:(\d+\.\d+)(?:-[\w.]+)?\z/, 1] }

    it "docker-compose.yml pins an exact major.minor Postgres image, not a floating tag" do
      expect(compose_image).to match(/\Apostgres:\d+\.\d+(-[\w.]+)?\z/)
    end

    it "the CI job starts the same Postgres image as docker-compose.yml" do
      ci_images = repo_root.join(".gitlab-ci.yml").read.scan(/\bpostgres:[\w.-]+/)

      expect(ci_images).not_to be_empty
      expect(ci_images.uniq).to eq([ compose_image ])
    end

    it "the database the suite runs on is the pinned version, the one the committed schema.rb was dumped with" do
      server_version = ActiveRecord::Base.connection.select_value("SHOW server_version")[/\A\d+\.\d+/]

      expect(pinned_version).not_to be_nil, "docker-compose.yml doesn't pin an exact version (#{compose_image})"
      expect(server_version).to eq(pinned_version)
    end
  end
end
