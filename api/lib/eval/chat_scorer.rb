module Eval
  # Runs the committed chat eval sets (eval/chat) through Chat::Orchestrator against one LLM
  # adapter and aggregates the R28 numbers: per-intent pass/fail, the schema-valid rate, the
  # out-of-scope fallback rate, the "you booked me for Friday" case, p95 latency per LLM call and
  # cost per conversation. Each case runs as a new user inside a transaction that is rolled back,
  # so the eval leaves nothing in the database.
  class ChatScorer
    EVAL_DIR = Rails.root.join("eval/chat")
    PRICES_PATH = Rails.root.join("eval/prices.yml")
    # An intent passes when at least this share of its labeled utterances routes to it.
    INTENT_PASS_THRESHOLD = 0.8
    BOOKING_BAIT_ID = "booking-claim-bait".freeze

    # adapter: responds to #complete(payload, timeout:) like an LLM provider adapter.
    # prices: per-million-token prices keyed by model id (default eval/prices.yml).
    # min_interval: seconds between the starts of two LLM calls, to stay inside free-tier rate
    # limits. Waiting isn't counted as latency.
    def initialize(adapter:, clock: nil, prices: nil, min_interval: 0, sleeper: nil)
      @meter = Meter.new(adapter, clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                         min_interval, sleeper || ->(seconds) { sleep(seconds) })
      @prices = prices || YAML.load_file(PRICES_PATH)
      @model = adapter.model
    end

    def call
      @routed = Hash.new { |hash, intent| hash[intent] = [] }
      @conversations = []
      @adversarial = {}
      @rate_limited = false
      begin
        score_intents
        score_conversations
        score_adversarial
      rescue Llm::RateLimitError
        # Stop at the first 429; cases that didn't run count as failures.
        @rate_limited = true
      end
      report
    end

    private

    attr_reader :meter

    def score_intents
      intent_set.each do |intent, utterances|
        utterances.each do |utterance|
          result = as_new_user { |user_id| send_message(user_id, utterance) }
          @routed[intent] << (result&.intent == intent)
        end
      end
    end

    def score_conversations
      conversations.each do |conversation|
        first_call = meter.calls.size
        valid = as_new_user do |user_id|
          finished = conversation["turns"].all? { |turn| send_message(user_id, turn["user"]) }
          finished && Chat::AssessmentSchema.valid?(Assessment.find_by(user_id: user_id)&.data)
        end
        @conversations << { valid: valid == true, cost: cost(meter.calls.drop(first_call)) }
      end
    end

    def score_adversarial
      adversarial_inputs.each do |input|
        result = as_new_user { |user_id| send_message(user_id, input["message"]) }
        @adversarial[input["id"]] = result.present? && !Chat::ReplyGuard.unbacked_claim?(result.reply.to_s)
      end
    end

    # The orchestrator's result, or nil when the LLM call failed. A 429 propagates.
    def send_message(user_id, message)
      Chat::Orchestrator.new(user_id: user_id, llm_client: Llm::Client.new(primary: meter)).handle(message: message)
    rescue Llm::RateLimitError
      raise
    rescue Llm::Error
      nil
    end

    def as_new_user
      value = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        value = yield SecureRandom.uuid
        raise ActiveRecord::Rollback
      end
      value
    end

    def report
      intents = intent_set.to_h do |intent, utterances|
        correct = @routed[intent].count(true)
        [ intent, { correct: correct, total: utterances.size, pass: correct.fdiv(utterances.size) >= INTENT_PASS_THRESHOLD } ]
      end
      {
        intents: intents,
        intent_coverage: intents.count { |_, score| score[:pass] }.fdiv(intents.size),
        schema_valid_rate: @conversations.count { |conversation| conversation[:valid] }.fdiv(conversations.size),
        out_of_scope_fallback: fallback_rate,
        no_false_booking: @adversarial[BOOKING_BAIT_ID] == true,
        p95_latency_ms: p95(meter.latencies_ms),
        cost_per_conversation_usd: cost_per_conversation,
        llm_calls: meter.calls.size,
        rate_limited: @rate_limited
      }
    end

    def fallback_rate
      out_of_scope = @routed["out-of-scope"].count(true)
      adversarial = @adversarial.values.count(true)
      (out_of_scope + adversarial).fdiv(intent_set.fetch("out-of-scope").size + adversarial_inputs.size)
    end

    # Nearest rank: the smallest latency with at least 95% of calls at or below it.
    def p95(latencies)
      return if latencies.empty?

      latencies.sort[((latencies.size * 95) + 99) / 100 - 1]
    end

    # Unknown (nil) unless every call in every conversation that ran reported usage and the model
    # has a price.
    def cost_per_conversation
      costs = @conversations.map { |conversation| conversation[:cost] }
      return if costs.empty? || costs.any?(&:nil?)

      costs.sum / costs.size
    end

    def cost(usages)
      price = @prices[@model]
      return if price.nil? || usages.any?(&:nil?)

      usages.sum do |usage|
        (usage[:input_tokens] * price.fetch("input_per_mtok")) + (usage[:output_tokens] * price.fetch("output_per_mtok"))
      end / 1_000_000.0
    end

    def intent_set
      @intent_set ||= YAML.load_file(EVAL_DIR.join("intents.yml"))
    end

    def conversations
      @conversations_set ||= YAML.load_file(EVAL_DIR.join("conversations.yml"))
    end

    # A `repeat` entry builds its message by repeating `text` and cutting it to `length` characters.
    def adversarial_inputs
      @adversarial_inputs ||= YAML.load_file(EVAL_DIR.join("adversarial.yml")).map do |entry|
        next entry unless entry["repeat"]

        text, length = entry["repeat"].values_at("text", "length")
        entry.merge("message" => (text * ((length / text.length) + 1))[0, length])
      end
    end

    # Wraps the adapter to time each call, keep its token usage and pace calls.
    class Meter
      attr_reader :calls, :latencies_ms

      def initialize(adapter, clock, min_interval, sleeper)
        @adapter = adapter
        @clock = clock
        @min_interval = min_interval
        @sleeper = sleeper
        @calls = []
        @latencies_ms = []
        @last_start = nil
      end

      def model
        @adapter.model
      end

      def complete(payload, timeout:)
        pace
        started = @last_start = @clock.call
        response = @adapter.complete(payload, timeout: timeout)
        @calls << response.usage
        response
      ensure
        @latencies_ms << ((@clock.call - started) * 1000) if started
      end

      private

      def pace
        return unless @min_interval.positive? && @last_start

        wait = @min_interval - (@clock.call - @last_start)
        @sleeper.call(wait) if wait.positive?
      end
    end
  end
end
