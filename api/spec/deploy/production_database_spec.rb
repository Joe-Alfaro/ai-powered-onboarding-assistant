require "rails_helper"
require "open3"
require "socket"

# Deploy readiness: production uses one hosted Postgres database (DATABASE_URL) for the app,
# Solid Queue and Solid Cache. These run the real production boot in a child process against an
# empty database, as a fresh deploy's entrypoint does.
RSpec.describe "Production database setup" do
  # Answers the Supabase Auth admin API in a child process: the first create of each email
  # succeeds, later ones get 422 email_exists, as the real API does.
  class FakeAuthServer
    attr_reader :created

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @created = []
      @thread = Thread.new { loop { handle(@server.accept) } rescue IOError }
    end

    def url
      "http://127.0.0.1:#{@server.addr[1]}"
    end

    def close
      @thread.kill
      @server.close
    end

    private

    def handle(client)
      request_line = client.gets.to_s
      headers = {}
      while (line = client.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.downcase] = value.strip
      end
      body = JSON.parse(client.read(headers.fetch("content-length", "0").to_i).presence || "{}")
      email = body["email"]
      status, reply =
        if !request_line.start_with?("POST /auth/v1/admin/users") then [ 404, {} ]
        elsif @created.include?(email) then [ 422, { error_code: "email_exists" } ]
        else @created << email; [ 200, { id: SecureRandom.uuid, email: email } ]
        end
      payload = reply.to_json
      client.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{payload.bytesize}\r\nConnection: close\r\n\r\n#{payload}")
    ensure
      client.close
    end
  end

  let(:database) { "deploy_check_#{Process.pid}_#{SecureRandom.hex(3)}" }
  let(:test_config) { ActiveRecord::Base.connection_db_config.configuration_hash }
  let(:database_url) do
    "postgres://#{test_config[:username]}:#{test_config[:password]}@#{test_config[:host]}:#{test_config[:port]}/#{database}"
  end
  let(:supabase_url) { "http://127.0.0.1:9" } # closed port: any unplanned Supabase call fails

  # Placeholder, non-secret values: enough for the production boot.
  let(:production_env) do
    {
      "RAILS_ENV" => "production",
      "DATABASE_URL" => database_url,
      "SECRET_KEY_BASE" => "placeholder-#{"0" * 64}",
      "WEB_ORIGIN" => "https://web.example.com",
      "SUPABASE_URL" => supabase_url,
      "SUPABASE_JWKS_URL" => "#{supabase_url}/auth/v1/.well-known/jwks.json",
      "SUPABASE_SERVICE_ROLE_KEY" => "placeholder",
      "STORAGE_BUCKET" => "id-documents",
      "RAILS_LOG_LEVEL" => "error"
    }
  end

  def rails(*args)
    output, status = Open3.capture2e(production_env, "bin/rails", *args, chdir: Rails.root.to_s)
    raise "bin/rails #{args.join(' ')} failed:\n#{output.lines.last(30).join}" unless status.success?

    output
  end

  def tables
    PG.connect(database_url) do |connection|
      connection.exec("SELECT tablename FROM pg_tables WHERE schemaname = 'public'").column_values(0)
    end
  end

  # Outside the example's transaction, through the server's maintenance database.
  def admin(sql)
    PG.connect(database_url.sub(%r{/#{database}\z}, "/postgres")) { |connection| connection.exec(sql) }
  end

  before { admin("CREATE DATABASE #{database}") }
  after { admin("DROP DATABASE IF EXISTS #{database} WITH (FORCE)") }

  describe "db:prepare on an empty database" do
    before { rails("db:prepare") }

    it "creates the app tables" do
      expect(tables).to include("slots", "bookings", "audit_events", "document_uploads", "schema_migrations")
    end

    it "creates the Solid Queue tables in the same database" do
      expect(tables).to include("solid_queue_jobs", "solid_queue_recurring_tasks", "solid_queue_scheduled_executions",
                                "solid_queue_processes", "solid_queue_semaphores")
    end

    it "creates the Solid Cache table in the same database" do
      expect(tables).to include("solid_cache_entries")
    end

    it "doesn't run the seed, which calls Supabase Auth" do
      expect(PG.connect(database_url) { |c| c.exec("SELECT count(*) FROM slots").getvalue(0, 0).to_i }).to eq(0)
    end

    it "points Solid Queue, Solid Cache and the app at the one database, with no prepared statements" do
      output = rails("runner", <<~RUBY)
        Rails.cache.write("deploy-check", "ok")
        puts [ ActiveRecord::Base.connection.current_database, SolidQueue::Job.connection.current_database,
               SolidCache::Entry.connection.current_database, Rails.cache.read("deploy-check"),
               ActiveRecord::Base.connection_db_config.configuration_hash[:prepared_statements].inspect ].join(" ")
      RUBY

      expect(output.lines.last.split).to eq([ database, database, database, "ok", "false" ])
    end

    it "registers the recurring purge job with Solid Queue" do
      output = rails("runner", <<~RUBY)
        configuration = SolidQueue::Configuration.new
        scheduler = configuration.configured_processes.find { |process| process.kind == :scheduler }
        SolidQueue::RecurringTask.create_or_update_all(scheduler.attributes.fetch(:recurring_tasks))
        puts SolidQueue::RecurringTask.pluck(:key, :class_name).map { |pair| pair.join("=") }.join(" ")
      RUBY

      expect(output.lines.last.split).to include("purge_expired_document_uploads=Documents::PurgeExpiredUploadsJob")
    end

    it "is safe to run again" do
      expect { rails("db:prepare") }.not_to raise_error
    end
  end

  describe "db:seed in production" do
    let(:auth) { FakeAuthServer.new }
    let(:supabase_url) { auth.url }

    after { auth.close }

    def slot_counts
      PG.connect(database_url) do |connection|
        connection.exec(<<~SQL).first.transform_values(&:to_i)
          SELECT count(*) AS total, count(*) FILTER (WHERE starts_at <= now() AT TIME ZONE 'UTC') AS past,
                 count(*) FILTER (WHERE extract(hour FROM starts_at) NOT BETWEEN 14 AND 19) AS outside_utc_hours
          FROM slots
        SQL
      end
    end

    it "creates only the demo users, and future slots at the fixed UTC hours, and is idempotent" do
      rails("db:prepare")
      first = rails("db:seed")
      after_first = slot_counts
      second = rails("db:seed")

      expect(auth.created).to eq(Seeds::DemoData::DEMO_EMAILS)
      expect(first).to include("demo@example.com")
      expect(second).to include("(already existed)")
      expect(after_first["total"]).to be_positive
      expect(after_first.values_at("past", "outside_utc_hours")).to eq([ 0, 0 ])
      expect(slot_counts).to eq(after_first)
    end
  end
end
