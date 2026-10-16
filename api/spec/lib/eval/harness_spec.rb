require "rails_helper"
require "rake"

# Eval::Harness is `rake ai:eval` (R27, R28): the OCR golden set plus the chat sets on one provider,
# or on every candidate with PROVIDERS=all. It prints a scorecard and writes one results file.
# Specs inject a fake adapter factory and a fake OCR scorer; no real provider is ever called.
RSpec.describe "Eval::Harness" do
  let(:results_dir) { Pathname(Dir.mktmpdir) }
  let(:out) { StringIO.new }
  let(:built) { [] }
  let(:adapters) { {} }
  # Builds a fake adapter per candidate and remembers what it was asked for.
  let(:adapter_factory) do
    lambda do |provider:, model:|
      built << { provider: provider, model: model }
      adapters[[ provider, model ]] = eval_llm(provider: provider, model: model)
    end
  end
  let(:ocr_report) do
    {
      all: { full_name: 0.9, date_of_birth: 1.0, address: 0.8 },
      hard: { full_name: 0.5, date_of_birth: 1.0, address: 0.25 },
      counts: { all: 30, hard: 6 },
      misses: [ { id: "027", field: :full_name, expected: "Lena N Placeholder", read: "LENAN Placeholder" } ]
    }
  end
  let(:ocr_scorer) { instance_double("Eval::OcrScorer", call: ocr_report) }

  after { FileUtils.rm_rf(results_dir) }

  def run_harness(env)
    Eval::Harness.new(env: env, adapter_factory: adapter_factory, ocr_scorer: ocr_scorer,
                      results_dir: results_dir, out: out).call
  end

  def results_files
    results_dir.glob("*.json")
  end

  def results
    expect(results_files.size).to eq(1)
    JSON.parse(results_files.first.read)
  end

  def provider_entry(name)
    results.fetch("providers").find { |entry| entry["name"] == name }
  end

  def output_line(pattern)
    out.string.lines.find { |line| line.match?(pattern) }
  end

  describe "R27: one command runs OCR and the chat sets and prints a scorecard" do
    let(:env) { { "LLM_PROVIDER" => "groq", "GROQ_API_KEY" => "test-groq-key" } }

    it "R27: prints per-field OCR accuracy, with hard cases reported separately" do
      run_harness(env)

      all_section, hard_section = out.string.split(/hard cases/i, 2)
      expect(hard_section).not_to be_nil
      expect(all_section).to match(/full_name\D+90(\.0)?%/).and match(/address\D+80(\.0)?%/)
      expect(hard_section).to match(/full_name\D+50(\.0)?%/).and match(/address\D+25(\.0)?%/)
    end

    it "R27: prints pass or fail for every intent in the intent list" do
      run_harness(env)

      ChatHelpers::INTENTS.each do |intent|
        expect(output_line(/#{Regexp.escape(intent)}\b.*\b(pass|fail)\b/i)).to be_present, intent
      end
    end

    it "R27: without PROVIDERS, runs the chat sets on LLM_PROVIDER and LLM_MODEL" do
      run_harness(env.merge("LLM_MODEL" => "groq-eval-model"))

      expect(built).to eq([ { provider: "groq", model: "groq-eval-model" } ])
      expect(results.fetch("providers").size).to eq(1)
      expect(results.fetch("providers").first).to include("provider" => "groq", "model" => "groq-eval-model",
                                                          "status" => "completed")
    end

    it "R27: without PROVIDERS or LLM_PROVIDER, still scores OCR and skips the chat sets with a message" do
      expect { run_harness({}) }.not_to raise_error

      expect(out.string).to match(/hard cases/i)
      expect(output_line(/skipped/i)).to match(/LLM_PROVIDER/)
      expect(built).to be_empty
    end

    it "R27: writes the OCR and chat results to one JSON file in the results directory" do
      run_harness(env)

      expect(results.fetch("ocr")).to include(
        "all" => { "full_name" => 0.9, "date_of_birth" => 1.0, "address" => 0.8 },
        "hard" => { "full_name" => 0.5, "date_of_birth" => 1.0, "address" => 0.25 },
        "counts" => { "all" => 30, "hard" => 6 }
      )
      entry = results.fetch("providers").first
      expect(entry.keys).to include(
        "name", "provider", "model", "status", "intents", "intent_coverage", "schema_valid_rate",
        "out_of_scope_fallback", "no_false_booking", "p95_latency_ms", "cost_per_conversation_usd", "rate_limited"
      )
      expect(entry.fetch("intents").keys).to match_array(ChatHelpers::INTENTS)
      expect(entry).to include("intent_coverage" => 1.0, "schema_valid_rate" => 1.0, "no_false_booking" => true)
    end

    it "R27: each run writes its own results file instead of overwriting the last one" do
      run_harness(env)
      travel 1.minute
      run_harness(env)

      expect(results_files.size).to eq(2)
    end
  end

  describe "R28: PROVIDERS=all runs the chat sets unchanged against every candidate" do
    let(:all_keys) do
      { "PROVIDERS" => "all", "CLAUDE_API_KEY" => "test-claude-key", "GROQ_API_KEY" => "test-groq-key",
        "GEMINI_API_KEY" => "test-gemini-key", "OLLAMA_BASE_URL" => "http://localhost:11434" }
    end

    it "R28: runs Claude Haiku, Claude Sonnet, Groq, Gemini and Ollama, each on its candidate model" do
      run_harness(all_keys)

      expected = EvalHelpers::CANDIDATES.values.map { |candidate| candidate.slice(:provider, :model) }
      expect(built).to match_array(expected)
      EvalHelpers::CANDIDATES.each do |name, candidate|
        expect(provider_entry(name)).to include("provider" => candidate[:provider], "model" => candidate[:model],
                                                "status" => "completed")
      end
    end

    it "R28: sends every candidate exactly the same eval messages" do
      run_harness(all_keys)

      sent = adapters.values.map { |adapter| adapter.payloads.map { |payload| last_user_message(payload) }.sort }
      expect(sent.uniq.size).to eq(1)
      expect(sent.first).not_to be_empty
    end

    it "R28: reports every R28 number for every candidate" do
      run_harness(all_keys)

      EvalHelpers::CANDIDATES.each_key do |name|
        entry = provider_entry(name)
        expect(entry.values_at("intent_coverage", "schema_valid_rate", "out_of_scope_fallback", "p95_latency_ms"))
          .to all(be_a(Numeric)), name
        expect(entry).to include("rate_limited" => false)
        expect(entry).to have_key("cost_per_conversation_usd")
      end
    end

    it "R28: a candidate cut short by a rate limit is still reported, and the others still run" do
      limited = lambda do |provider:, model:|
        adapter = adapter_factory.call(provider: provider, model: model)
        provider == "groq" ? FakeLlmAdapter.new(provider: provider, model: model).fail_with(Llm::RateLimitError) : adapter
      end

      expect do
        Eval::Harness.new(env: all_keys, adapter_factory: limited, ocr_scorer: ocr_scorer,
                          results_dir: results_dir, out: out).call
      end.not_to raise_error

      expect(provider_entry("groq")).to include("rate_limited" => true)
      expect(output_line(/groq\b.*rate.limit/i)).to be_present
      expect(provider_entry("gemini")).to include("status" => "completed", "rate_limited" => false)
    end

    it "R28: prints each candidate's p95 latency, schema-valid rate and cost per conversation" do
      run_harness(all_keys)

      expect(out.string).to match(/p95/i).and match(/schema.valid/i).and match(/cost/i)
      EvalHelpers::CANDIDATES.each_key { |name| expect(out.string).to include(name) }
    end
  end

  describe "R21 [gotcha]: missing keys are skipped with a message, and no candidate is left out" do
    it "R21: with only free or local keys set, completes on those providers and skips the rest" do
      env = { "PROVIDERS" => "all", "GROQ_API_KEY" => "test-groq-key", "OLLAMA_BASE_URL" => "http://localhost:11434" }

      expect { run_harness(env) }.not_to raise_error

      expect(built.map { |candidate| candidate[:provider] }).to match_array(%w[groq ollama])
      expect(provider_entry("groq")).to include("status" => "completed")
      expect(provider_entry("ollama")).to include("status" => "completed")
      %w[claude-haiku claude-sonnet gemini].each do |name|
        variable = EvalHelpers::CANDIDATES.dig(name, :variable)
        expect(provider_entry(name)).to include("status" => "skipped")
        expect(provider_entry(name).fetch("skip_reason")).to include(variable)
        expect(output_line(/#{Regexp.escape(name)}\b.*skipped/i)).to include(variable)
      end
    end

    it "R21: with no keys at all, reports every candidate as skipped instead of crashing" do
      expect { run_harness("PROVIDERS" => "all") }.not_to raise_error

      expect(built).to be_empty
      expect(results.fetch("providers").map { |entry| entry["name"] }).to match_array(EvalHelpers::CANDIDATES.keys)
      expect(results.fetch("providers").map { |entry| entry["status"] }).to all(eq("skipped"))
    end

    it "R21: without PROVIDERS, a selected provider whose key is missing is skipped with a message" do
      expect { run_harness("LLM_PROVIDER" => "gemini") }.not_to raise_error

      expect(built).to be_empty
      expect(output_line(/skipped/i)).to include("GEMINI_API_KEY")
    end
  end

  describe "R15, R20: the results files hold no personal data, prompt text or secrets" do
    let(:env) do
      { "PROVIDERS" => "all", "CLAUDE_API_KEY" => "secret-claude-value-1234", "GROQ_API_KEY" => "secret-groq-value-5678" }
    end

    before { run_harness(env) }

    let(:written) { results_files.map(&:read).join("\n") }

    it "R27: writes no golden-set name, date of birth or address, including OCR misses" do
      golden = JSON.parse(Rails.root.join("eval/golden/labels.json").read).flat_map { |label| label["expected"].values }
      miss_values = ocr_report[:misses].flat_map { |miss| miss.values_at(:expected, :read) }

      (golden + miss_values).each { |value| expect(written).not_to include(value) }
    end

    it "R27: writes no eval message, LLM reply or system prompt text" do
      replies = scripted_conversations.flat_map { |conversation| conversation["turns"].map { |turn| turn.dig("scripted_llm", "reply") } }
      prompt_lines = Chat::Prompt.system.lines.map(&:strip).select { |line| line.length > 20 }

      (eval_messages + replies + prompt_lines).each { |text| expect(written).not_to include(text) }
    end

    it "R27: writes and prints no API key value" do
      [ written, out.string ].each do |text|
        expect(text).not_to include("secret-claude-value-1234")
        expect(text).not_to include("secret-groq-value-5678")
      end
    end
  end
end

RSpec.describe "rake ai:eval" do
  before(:all) { Rails.application.load_tasks unless Rake::Task.task_defined?("ai:eval") }

  let(:results_dir) { Dir.mktmpdir }
  let(:golden_dir) { Pathname(Dir.mktmpdir) }

  # The task reads ENV, so clear every provider variable: no real provider may be called.
  around do |example|
    variables = EvalHelpers::PROVIDER_VARIABLES + %w[GOLDEN_DIR RESULTS_DIR]
    original = variables.to_h { |name| [ name, ENV.fetch(name, nil) ] }
    variables.each { |name| ENV.delete(name) }
    example.run
  ensure
    original.each { |name, value| ENV[name] = value }
  end

  after { FileUtils.rm_rf([ results_dir, golden_dir ]) }

  it "R27, R21: with PROVIDERS=all and no keys, scores OCR, skips every candidate and writes the results" do
    FileUtils.cp(ocr_fixture("clean_id.png"), golden_dir.join("001.png"))
    expected = { full_name: "Jane Q Sample", date_of_birth: "1985-03-14", address: "123 Fake St, Springfield, ZZ 00000" }
    golden_dir.join("labels.json").write(JSON.generate([
      { id: "001", image: "001.png", category: "clean", hard: true, hard_reason: "near miss", expected: expected }
    ]))
    ENV.update("PROVIDERS" => "all", "GOLDEN_DIR" => golden_dir.to_s, "RESULTS_DIR" => results_dir)

    task = Rake::Task["ai:eval"]
    task.reenable
    output = capture_stdout { task.invoke }

    expect(output).to match(/hard cases/i).and match(/full_name\D+100(\.0)?%/)
    EvalHelpers::CANDIDATES.each_key { |name| expect(output).to match(/#{Regexp.escape(name)}\b.*skipped/i) }
    files = Dir.glob(File.join(results_dir, "*.json"))
    expect(files.size).to eq(1)
    expect(JSON.parse(File.read(files.first)).fetch("providers").map { |entry| entry["status"] }).to all(eq("skipped"))
  end

  it "R27: writes to api/eval/results by default" do
    expect(Eval::Harness::DEFAULT_RESULTS_DIR.to_s).to eq(Rails.root.join("eval/results").to_s)
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
