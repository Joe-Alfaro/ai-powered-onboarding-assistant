module Eval
  # `rake ai:eval` (R27, R28): scores the OCR golden set and runs the chat sets on one provider
  # (LLM_PROVIDER and LLM_MODEL) or on every candidate (PROVIDERS=all, or a comma-separated list of
  # candidate names). Prints a scorecard and writes one new JSON file of aggregates per run. A
  # candidate without its key is reported as skipped, never left out (R21).
  class Harness
    DEFAULT_RESULTS_DIR = Rails.root.join("eval/results")
    CANDIDATES = {
      "claude-haiku" => { provider: "anthropic", model: "claude-haiku-4-5" },
      "claude-sonnet" => { provider: "anthropic", model: "claude-sonnet-5-5" },
      "groq" => { provider: "groq", model: Llm::Providers::DEFAULT_MODELS.fetch("groq") },
      "gemini" => { provider: "gemini", model: Llm::Providers::DEFAULT_MODELS.fetch("gemini") },
      "ollama" => { provider: "ollama", model: Llm::Providers::DEFAULT_MODELS.fetch("ollama") }
    }.freeze
    # Seconds between LLM calls per provider for a real run, under each free tier's requests- and
    # tokens-per-minute limits (about 2K tokens per call). Specs run unpaced.
    FREE_TIER_PACING = { "anthropic" => 1.5, "groq" => 15, "gemini" => 7, "ollama" => 0 }.freeze
    METRICS = %i[intent_coverage schema_valid_rate out_of_scope_fallback no_false_booking
                 no_diagnosis_or_outcome_claim p95_latency_ms
                 cost_per_conversation_usd llm_calls failed_llm_calls
                 failure_classes].freeze

    # adapter_factory: callable taking provider: and model:, returning an adapter.
    # ocr_scorer: responds to #call with Eval::OcrScorer's report.
    # pacing: seconds between LLM calls, keyed by provider.
    def initialize(env:, ocr_scorer:, adapter_factory: nil, results_dir: DEFAULT_RESULTS_DIR, out: $stdout, pacing: {})
      @env = env
      @ocr_scorer = ocr_scorer
      @adapter_factory = adapter_factory || ->(provider:, model:) { Llm::Providers.build(provider, model, env) }
      @results_dir = Pathname(results_dir)
      @out = out
      @pacing = pacing
    end

    def call
      ocr = @ocr_scorer.call
      print_ocr(ocr)
      providers = candidates.map { |candidate| run(candidate) }
      path = write(ocr, providers)
      @out.puts "Results written to #{path}"
      path
    end

    private

    # Each candidate is { name:, provider:, model: } plus skip_reason when it can't run.
    def candidates
      requested = @env["PROVIDERS"].to_s.strip
      return selected_provider if requested.empty?

      names = requested == "all" ? CANDIDATES.keys : requested.split(",").map(&:strip)
      names.map do |name|
        candidate = CANDIDATES[name]
        next { name: name, skip_reason: "unknown candidate; use one of #{CANDIDATES.keys.join(', ')}" } unless candidate

        { name: name, **candidate, skip_reason: missing_key(candidate[:provider]) }
      end
    end

    def selected_provider
      provider = @env["LLM_PROVIDER"].to_s.strip
      if provider.empty?
        @out.puts "Chat sets skipped: LLM_PROVIDER is not set (or set PROVIDERS=all)"
        return []
      end
      unless provider.in?(Llm::Providers::NAMES)
        return [ { name: provider, provider: provider, skip_reason: "LLM_PROVIDER must be one of #{Llm::Providers::NAMES.join(', ')}" } ]
      end

      model = @env["LLM_MODEL"].presence || Llm::Providers::DEFAULT_MODELS.fetch(provider)
      [ { name: provider, provider: provider, model: model, skip_reason: missing_key(provider) } ]
    end

    # Names the variable to set, never its value.
    def missing_key(provider)
      variable = Llm::Providers::KEY_VARIABLES.fetch(provider, "OLLAMA_BASE_URL")
      "#{variable} is not set" if @env[variable].blank?
    end

    def run(candidate)
      entry = { name: candidate[:name], provider: candidate[:provider], model: candidate[:model] }
      if candidate[:skip_reason]
        @out.puts "#{candidate[:name]}: skipped, #{candidate[:skip_reason]}"
        return entry.merge(status: "skipped", skip_reason: candidate[:skip_reason], intents: nil, rate_limited: false,
                           **METRICS.index_with(nil))
      end

      adapter = @adapter_factory.call(provider: candidate[:provider], model: candidate[:model])
      report = ChatScorer.new(adapter: adapter, min_interval: @pacing.fetch(candidate[:provider], 0)).call
      entry = entry.merge(status: "completed", **report)
      print_provider(entry)
      entry
    end

    def print_ocr(ocr)
      @out.puts "OCR golden set (#{Ocr::Extractor.version || 'tesseract not found'})"
      { "All documents" => :all, "Hard cases" => :hard }.each do |title, key|
        @out.puts "#{title} (#{ocr.dig(:counts, key)})"
        ocr[key].each { |field, accuracy| @out.puts format("  %-14s %5.1f%%", field, accuracy * 100) }
      end
      # Ids and fields only: the read and expected values stay out of the scorecard.
      misses = Array(ocr[:misses]).map { |miss| "#{miss[:id]} #{miss[:field]}" }
      @out.puts "OCR misses: #{misses.any? ? misses.join(', ') : 'none'}"
      @out.puts
    end

    def print_provider(entry)
      header = "#{entry[:name]} (#{entry[:provider]} #{entry[:model]}): completed, #{entry[:llm_calls]} LLM calls answered"
      header += ", #{entry[:failed_llm_calls]} failed (#{entry[:failure_classes].join(', ')})" if entry[:failed_llm_calls].positive?
      header += ", cut short by a rate limit (HTTP 429)" if entry[:rate_limited]
      @out.puts header
      entry[:intents].each do |intent, score|
        @out.puts format("  %-20s %2d/%-2d %s", intent, score[:correct], score[:total], score[:pass] ? "pass" : "fail")
      end
      @out.puts "  intent coverage #{percent(entry[:intent_coverage])}, schema-valid #{percent(entry[:schema_valid_rate])}, " \
                "out-of-scope fallback #{percent(entry[:out_of_scope_fallback])}, " \
                "no false booking #{entry[:no_false_booking] ? 'pass' : 'fail'}, " \
                "no diagnosis or outcome claim #{entry[:no_diagnosis_or_outcome_claim] ? 'pass' : 'fail'}"
      @out.puts "  p95 latency #{entry[:p95_latency_ms] ? "#{entry[:p95_latency_ms].round} ms" : 'n/a'}, " \
                "cost per conversation #{dollars(entry[:cost_per_conversation_usd])}"
      @out.puts
    end

    def percent(value)
      format("%.1f%%", value * 100)
    end

    def dollars(value)
      value ? format("$%.5f", value) : "unknown"
    end

    def write(ocr, providers)
      @results_dir.mkpath
      stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
      path = @results_dir.join("#{stamp}.json")
      path = @results_dir.join("#{stamp}-#{SecureRandom.hex(2)}.json") if path.exist?
      results = {
        generated_at: Time.current.utc.iso8601,
        ocr_engine: Ocr::Extractor.version,
        ocr: { all: ocr[:all], hard: ocr[:hard], counts: ocr[:counts],
               misses: Array(ocr[:misses]).map { |miss| miss.slice(:id, :field) } },
        providers: providers
      }
      path.write("#{JSON.pretty_generate(results)}\n")
      path
    end
  end
end
