require "rails_helper"

# R31: GET /health with the probes the app registers (Health::Check.probes), not injected fakes, so
# it tests what ships. Providers are stubbed only at their boundary: Supabase Storage and the LLM
# provider over HTTP with WebMock, Tesseract through PATH. The database probe is real.
RSpec.describe "GET /health with the registered probes", type: :request do
  BUCKET_URL = "https://project.supabase.test/storage/v1/bucket/spec-id-documents".freeze
  GROQ_MODELS_URL = "https://api.groq.com/openai/v1/models".freeze
  ANTHROPIC_MODELS_URL = "https://api.anthropic.com/v1/models".freeze
  ALL_OK = { "app" => "ok", "database" => "ok", "storage" => "ok", "ocr" => "ok", "llm" => "ok" }.freeze

  # Each example sets its own provider environment and starts with a fresh registry, so no cached
  # probe result leaks from one example to the next.
  around do |example|
    saved = ENV.to_h
    ENV["LLM_PROVIDER"] = "groq"
    ENV["GROQ_API_KEY"] = "test-groq-key"
    ENV["CLAUDE_API_KEY"] = "test-claude-key"
    %w[LLM_MODEL LLM_FALLBACK_PROVIDER LLM_FALLBACK_MODEL OLLAMA_BASE_URL].each { |name| ENV.delete(name) }
    reset_registered_probes
    example.run
  ensure
    ENV.replace(saved)
    reset_registered_probes
  end

  let!(:storage_stub) do
    stub_request(:get, BUCKET_URL)
      .with(headers: { "Authorization" => "Bearer spec-service-role-key" })
      .to_return(status: 200, body: { id: "spec-id-documents", name: "spec-id-documents", public: false }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  let!(:llm_stub) do
    stub_request(:get, GROQ_MODELS_URL)
      .with(headers: { "Authorization" => "Bearer test-groq-key" })
      .to_return(status: 200, body: { object: "list", data: [ { id: "openai/gpt-oss-20b", object: "model" } ] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  def reset_registered_probes
    Health::Check.instance_variable_set(:@probes, nil)
  end

  def statuses
    response.parsed_body.fetch("checks").transform_values { |check| check.fetch("status") }
  end

  # A PATH holding only the given executables, so `tesseract` resolves to a script or not at all.
  def with_path(scripts = {})
    Dir.mktmpdir("path") do |dir|
      scripts.each do |name, body|
        file = File.join(dir, name)
        File.write(file, "#!/bin/sh\n#{body}\n")
        File.chmod(0o755, file)
      end
      ENV["PATH"] = dir
      yield
    end
  end

  def without_tesseract(&)
    with_path(&)
  end

  def hanging_tesseract(&)
    with_path("tesseract" => "exec /bin/sleep 30", &)
  end

  def stub_storage_status(status)
    remove_request_stub(storage_stub)
    stub_request(:get, BUCKET_URL).to_return(status: status, body: { statusCode: status.to_s, error: "stubbed" }.to_json)
  end

  def stub_llm_status(status)
    remove_request_stub(llm_stub)
    stub_request(:get, GROQ_MODELS_URL).to_return(status: status, body: { error: { message: "stubbed #{status}" } }.to_json)
  end

  it "R31: reports every dependency as ok with a 200 when storage, OCR, the LLM and the database are up" do
    get "/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["status"]).to eq("ok")
    expect(statuses).to eq(ALL_OK)
  end

  describe "OCR (a tesseract --version check)" do
    it "R31: reports ocr as ok when tesseract can be run" do
      get "/health"

      expect(statuses["ocr"]).to eq("ok")
    end

    it "R31: reports ocr as down when tesseract isn't on the PATH" do
      without_tesseract { get "/health" }

      expect(statuses["ocr"]).to eq("down")
    end

    it "R31: reports ocr as down when tesseract exits with an error" do
      with_path("tesseract" => "exit 1") { get "/health" }

      expect(statuses["ocr"]).to eq("down")
    end

    it "R31: reports ocr as down within 3 s when tesseract hangs" do
      seconds = elapsed_seconds { hanging_tesseract { get "/health" } }

      expect(statuses["ocr"]).to eq("down")
      expect(seconds).to be < 3
    end
  end

  describe "storage (a bucket metadata call to Supabase Storage)" do
    it "R31: reports storage as ok when the bucket lookup returns 200, using the service role key" do
      get "/health"

      expect(statuses["storage"]).to eq("ok")
      expect(storage_stub).to have_been_requested.once
    end

    [ 500, 503 ].each do |status|
      it "R31: reports storage as down when Storage returns #{status}" do
        stub_storage_status(status)

        get "/health"

        expect(statuses["storage"]).to eq("down")
      end
    end

    it "R31: reports storage as down when the bucket doesn't exist" do
      stub_storage_status(404)

      get "/health"

      expect(statuses["storage"]).to eq("down")
    end

    it "R31: reports storage as down when the request times out" do
      remove_request_stub(storage_stub)
      stub_request(:get, BUCKET_URL).to_timeout

      get "/health"

      expect(statuses["storage"]).to eq("down")
    end

    it "R31: reports storage as down when the connection is refused" do
      remove_request_stub(storage_stub)
      stub_request(:get, BUCKET_URL).to_raise(Errno::ECONNREFUSED)

      get "/health"

      expect(statuses["storage"]).to eq("down")
    end

    it "R31: reports storage as down within 3 s when Storage accepts the connection and never answers" do
      HangingServer.open do |server|
        ENV["SUPABASE_URL"] = server.url
        reset_registered_probes

        seconds = elapsed_seconds { get "/health" }

        expect(statuses["storage"]).to eq("down")
        expect(seconds).to be < 3
      end
    end

    it "R31: repeated pings within the cache window call Storage once" do
      5.times { get "/health" }

      expect(storage_stub).to have_been_requested.once
    end
  end

  describe "LLM (the provider's model list endpoint)" do
    it "R31: reports llm as ok when the model list returns 200, without spending a completion" do
      get "/health"

      expect(statuses["llm"]).to eq("ok")
      expect(llm_stub).to have_been_requested.once
      expect(a_request(:post, /api\.groq\.com/)).not_to have_been_made
    end

    it "R31: probes the configured provider, so switching LLM_PROVIDER switches the probe" do
      ENV["LLM_PROVIDER"] = "anthropic"
      anthropic = stub_request(:get, ANTHROPIC_MODELS_URL)
                    .with(headers: { "x-api-key" => "test-claude-key" })
                    .to_return(status: 200, body: { data: [ { id: "claude-haiku-4-5", type: "model" } ] }.to_json,
                               headers: { "Content-Type" => "application/json" })

      get "/health"

      expect(statuses["llm"]).to eq("ok")
      expect(anthropic).to have_been_requested.once
      expect(llm_stub).not_to have_been_requested
      expect(a_request(:post, /api\.anthropic\.com/)).not_to have_been_made
    end

    [ 500, 503, 401, 429 ].each do |status|
      it "R31: reports llm as down when the provider returns #{status}" do
        stub_llm_status(status)

        get "/health"

        expect(statuses["llm"]).to eq("down")
      end
    end

    it "R31: reports llm as down when the request times out" do
      remove_request_stub(llm_stub)
      stub_request(:get, GROQ_MODELS_URL).to_timeout

      get "/health"

      expect(statuses["llm"]).to eq("down")
    end

    it "R31: reports llm as down when the connection is refused" do
      remove_request_stub(llm_stub)
      stub_request(:get, GROQ_MODELS_URL).to_raise(Errno::ECONNREFUSED)

      get "/health"

      expect(statuses["llm"]).to eq("down")
    end

    it "R31: reports llm as down, not an error, when no provider is configured" do
      ENV.delete("LLM_PROVIDER")

      get "/health"

      expect(response).to have_http_status(:ok)
      expect(statuses["llm"]).to eq("down")
    end

    it "R31: reports llm as down within 3 s when the provider accepts the connection and never answers" do
      HangingServer.open do |server|
        ENV["LLM_PROVIDER"] = "ollama"
        ENV["OLLAMA_BASE_URL"] = server.url

        seconds = elapsed_seconds { get "/health" }

        expect(statuses["llm"]).to eq("down")
        expect(seconds).to be < 3
      end
    end

    it "R31: repeated pings within the cache window make one provider call" do
      5.times { get "/health" }

      expect(llm_stub).to have_been_requested.once
      expect(statuses["llm"]).to eq("ok")
    end

    it "R31: a down provider is also cached, so pings don't hammer it" do
      stub = stub_llm_status(500)

      5.times { get "/health" }

      expect(stub).to have_been_requested.once
    end

    it "R31: probes the provider again once the cache window (at most 5 minutes) has passed" do
      get "/health"
      travel(5.minutes + 1.second) { get "/health" }

      expect(llm_stub).to have_been_requested.twice
    end
  end

  describe "breaking one dependency changes only its status" do
    it "R31: breaking storage changes only storage, with a 200 and an overall degraded" do
      stub_storage_status(500)

      get "/health"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("degraded")
      expect(statuses).to eq(ALL_OK.merge("storage" => "down"))
    end

    it "R31: breaking OCR changes only ocr, with a 200 and an overall degraded" do
      without_tesseract { get "/health" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("degraded")
      expect(statuses).to eq(ALL_OK.merge("ocr" => "down"))
    end

    it "R31: breaking the LLM provider changes only llm, with a 200 and an overall degraded" do
      stub_llm_status(500)

      get "/health"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("degraded")
      expect(statuses).to eq(ALL_OK.merge("llm" => "down"))
    end

    it "R31: storage, OCR and the LLM all down still returns 200, because only the database gives a 503" do
      stub_storage_status(503)
      stub_llm_status(503)

      without_tesseract { get "/health" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("degraded")
      expect(statuses).to eq(ALL_OK.merge("storage" => "down", "ocr" => "down", "llm" => "down"))
    end

    context "when the database is unreachable" do
      # Only the database probe is swapped, for a real connection to a port nothing listens on;
      # the storage, OCR and LLM probes are the registered ones.
      before do
        allow(Health::Check).to receive(:probes).and_wrap_original do |original|
          original.call.merge(database: Health::Probes::Database.new(unreachable_database))
        end
      end

      it "R31: reports only the database as down and returns 503" do
        get "/health"

        expect(response).to have_http_status(:service_unavailable)
        expect(response.parsed_body["status"]).to eq("down")
        expect(statuses).to eq(ALL_OK.merge("database" => "down"))
      end
    end
  end

  it "R31: responds within 6 s when storage, OCR and the LLM all hang" do
    HangingServer.open do |server|
      ENV["SUPABASE_URL"] = server.url
      ENV["LLM_PROVIDER"] = "ollama"
      ENV["OLLAMA_BASE_URL"] = server.url

      seconds = elapsed_seconds { hanging_tesseract { get "/health" } }

      expect(response).to have_http_status(:ok)
      expect(statuses).to eq(ALL_OK.merge("storage" => "down", "ocr" => "down", "llm" => "down"))
      expect(seconds).to be < 6
    end
  end
end
