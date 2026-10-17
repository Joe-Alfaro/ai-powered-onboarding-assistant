# Performance tooling (R22, R23, R24, R38). docs/performance.md has the method and the results.
namespace :perf do
  base_url = -> { ENV.fetch("PERF_BASE_URL", "http://localhost:3001") }
  tokens_file = -> { Pathname(ENV.fetch("PERF_TOKENS_FILE", Rails.root.join("tmp/perf-tokens.json").to_s)) }

  load_token = lambda do |index|
    tokens = JSON.parse(tokens_file.call.read)
    tokens.fetch(index % tokens.size)
  rescue Errno::ENOENT
    abort "No tokens at #{tokens_file.call}: run bin/rake perf:users first"
  end

  run_timing = lambda do |name, replies, success|
    log_file = ENV["PERF_LOG_FILE"].presence
    report = Perf::TimingReport.new(name: name, replies: replies, success: success,
                                    log_text: log_file && File.read(log_file))
    puts report.lines
    puts JSON.generate(report.to_h.merge(base_url: base_url.call,
                                         measured_at: Time.current.utc.iso8601))
  end

  client = ->(index) { Perf::ApiClient.new(base_url: base_url.call, token: load_token.call(index)) }

  desc "Create PERF_USERS (default 20) load-test users in Supabase Auth with PERF_USER_PASSWORD, sign them in, " \
       "and write their access tokens to PERF_TOKENS_FILE (default tmp/perf-tokens.json)"
  task users: :environment do
    password = ENV["PERF_USER_PASSWORD"].presence || abort("Set PERF_USER_PASSWORD (any strong value; never commit it)")
    users = Perf::LoadUsers.default(password: password).call(Integer(ENV.fetch("PERF_USERS", "20")))
    path = tokens_file.call
    File.write(path, JSON.generate(users.map { |user| user[:access_token] }))
    File.chmod(0o600, path)
    puts "Signed in #{users.size} load-test users (#{users.first[:email]} to #{users.last[:email]})"
    puts "Tokens written to #{path}; they expire with the project's JWT expiry (an hour by default)"
  end

  desc "R23: time PERF_RUNS (default 20) golden-set uploads to the extracted-fields response against PERF_BASE_URL; " \
       "PERF_LOG_FILE adds the server-side Lograge durations"
  task ocr: :environment do
    golden_dir = ENV.fetch("GOLDEN_DIR", Rails.root.join("eval/golden").to_s)
    replies = Perf::OcrTiming.new(client: client.call(0), golden_dir: golden_dir,
                                  runs: Integer(ENV.fetch("PERF_RUNS", "20"))).call
    run_timing.call("OCR upload to extracted fields (POST /documents)", replies, Perf::OcrTiming.method(:success?))
  end

  desc "R24: time PERF_RUNS (default 20) bookings against PERF_BASE_URL; PERF_LOG_FILE (the API's log) gives the " \
       "server duration from each request's Lograge line"
  task booking: :environment do
    replies = Perf::BookingTiming.new(client: client.call(1), runs: Integer(ENV.fetch("PERF_RUNS", "20"))).call
    run_timing.call("Booking (POST /bookings)", replies, Perf::BookingTiming.method(:success?))
  end
end
