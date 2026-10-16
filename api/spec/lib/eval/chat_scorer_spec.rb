require "rails_helper"

# Eval::ChatScorer runs the committed chat eval sets (api/eval/chat) through Chat::Orchestrator
# against one LLM adapter and aggregates the R28 numbers. Specs use a fake adapter, never a real
# provider.
RSpec.describe "Eval::ChatScorer" do
  def score(adapter, **options)
    Eval::ChatScorer.new(adapter: adapter, **options).call
  end

  # How many of an intent's n utterances must route correctly for it to pass (80%, rounded up).
  def pass_mark(total)
    (total * Eval::ChatScorer::INTENT_PASS_THRESHOLD).ceil
  end

  describe "R1: per-intent pass/fail" do
    it "R1: reports pass for every intent in the intent list when every utterance routes to its intent" do
      report = score(eval_llm)

      expect(report[:intents].keys).to match_array(ChatHelpers::INTENTS)
      intent_set.each do |intent, utterances|
        expect(report[:intents][intent]).to eq(correct: utterances.size, total: utterances.size, pass: true)
      end
      expect(report[:intent_coverage]).to eq(1.0)
    end

    it "R1: an intent passes when at least 80% of its utterances route to it, and fails below that" do
      expect(Eval::ChatScorer::INTENT_PASS_THRESHOLD).to eq(0.8)
      passing = intent_set.fetch("ask-question")
      failing = intent_set.fetch("provide-details")
      misrouted = passing.first(passing.size - pass_mark(passing.size)) +
        failing.first(failing.size - pass_mark(failing.size) + 1)

      report = score(eval_llm { |message| llm_output("out-of-scope") if misrouted.include?(message) })

      expect(report[:intents]["ask-question"]).to eq(correct: pass_mark(passing.size), total: passing.size, pass: true)
      expect(report[:intents]["provide-details"])
        .to eq(correct: pass_mark(failing.size) - 1, total: failing.size, pass: false)
      expect(report[:intent_coverage]).to eq(0.8)
    end

    it "R1: an utterance whose LLM call fails counts as not routed, and the run carries on" do
      failed = intent_set.fetch("express-distress").first

      adapter = eval_llm { |message| raise Llm::TimeoutError if message == failed }
      report = score(adapter)

      total = intent_set.fetch("express-distress").size
      expect(report[:intents]["express-distress"]).to include(correct: total - 1, total: total)
      expect(report[:intents]["out-of-scope"]).to include(pass: true)
      expect(report[:rate_limited]).to be(false)
    end
  end

  describe "R2: schema-valid assessment rate on the scripted conversations" do
    it "R2: reports a 100% schema-valid rate when the LLM answers the scripted conversations as scripted" do
      expect(score(eval_llm)[:schema_valid_rate]).to eq(1.0)
    end

    it "R2: a conversation that ends without a saved, schema-valid assessment lowers the rate" do
      broken = scripted_conversations.first["turns"].last["user"]

      report = score(eval_llm { |message| llm_output("provide-details") if message == broken })

      total = scripted_conversations.size
      expect(report[:schema_valid_rate]).to eq((total - 1).fdiv(total))
    end
  end

  describe "R3: out-of-scope fallback" do
    let(:fallback_cases) { intent_set.fetch("out-of-scope").size + adversarial_inputs.size }

    it "R3: reports a 100% fallback rate when out-of-scope and hostile input all get the redirect" do
      expect(score(eval_llm)[:out_of_scope_fallback]).to eq(1.0)
    end

    it "R3: an out-of-scope utterance answered as another intent, or a hostile input that errors, is not a fallback" do
      answered = intent_set.fetch("out-of-scope").first
      injection = adversarial_message("prompt-injection")

      report = score(eval_llm do |message|
        raise Llm::ServerError if message == injection

        llm_output("ask-question", reply: "Sure, here you go.") if message == answered
      end)

      expect(report[:out_of_scope_fallback]).to eq((fallback_cases - 2).fdiv(fallback_cases))
    end
  end

  describe "R3 [gotcha]: 'you booked me for Friday, right?' with no booking claims no booking" do
    let(:bait) { adversarial_message(EvalHelpers::BOOKING_BAIT_ID) }

    it "R3: passes when the reply guard swaps an LLM booking claim for the template" do
      report = score(eval_llm { |message| llm_output("ask-question", reply: "Yes, you're booked for Friday at 3pm.") if message == bait })

      expect(report[:no_false_booking]).to be(true)
    end

    it "R3: passes when the LLM routes the bait to rescheduling and the user has no booking" do
      report = score(eval_llm { |message| llm_output("request-reschedule") if message == bait })

      expect(report[:no_false_booking]).to be(true)
    end

    it "R3: fails when a booking or time claim reaches the reply" do
      # A regression the eval exists to catch: the guard lets the LLM's text through.
      allow(Chat::ReplyGuard).to receive(:call) { |llm_reply:, template:| llm_reply.presence || template }

      report = score(eval_llm { |message| llm_output("ask-question", reply: "Yes, you're booked for Friday at 3pm.") if message == bait })

      expect(report[:no_false_booking]).to be(false)
    end
  end

  describe "R28: p95 latency" do
    it "R28: reports the nearest-rank 95th percentile of the LLM call latencies, in milliseconds" do
      now = 0.0
      calls = 0
      # Call n takes n * 10 ms on the injected clock.
      adapter = eval_llm do
        calls += 1
        now += calls * 0.01
        nil
      end

      report = score(adapter, clock: -> { now })

      expected_ms = (adapter.call_count * 0.95).ceil * 10
      expect(report[:p95_latency_ms]).to be_within(0.5).of(expected_ms)
    end

    it "R28: times only LLM calls, so inputs answered without one don't dilute the percentile" do
      now = 0.0
      adapter = eval_llm do
        now += 0.2
        nil
      end

      report = score(adapter, clock: -> { now })

      expect(report[:p95_latency_ms]).to be_within(0.5).of(200)
    end
  end

  describe "R28: cost per conversation from the price table" do
    let(:prices) { { "fake-model" => { "input_per_mtok" => 1.0, "output_per_mtok" => 2.0 } } }
    let(:usage) { { input_tokens: 1_000, output_tokens: 500 } }

    it "R28: averages each scripted conversation's token cost at the table's per-million-token prices" do
      report = score(eval_llm(usage: usage), prices: prices)

      per_call = ((1_000 * 1.0) + (500 * 2.0)) / 1_000_000
      turns = scripted_conversations.map { |conversation| conversation["turns"].size }
      expect(report[:cost_per_conversation_usd]).to be_within(1e-9).of(per_call * turns.sum.fdiv(turns.size))
    end

    it "R28: reports the cost as unknown, not zero, when the model has no price" do
      report = score(eval_llm(model: "unpriced-model", usage: usage), prices: prices)

      expect(report[:cost_per_conversation_usd]).to be_nil
    end

    it "R28: reports the cost as unknown, not zero, when the provider reports no token usage" do
      report = score(eval_llm, prices: prices)

      expect(report[:cost_per_conversation_usd]).to be_nil
    end

    it "R28: the committed price table prices every candidate model" do
      table = YAML.load_file(Rails.root.join("eval/prices.yml"))

      EvalHelpers::CANDIDATES.each_value do |candidate|
        price = table.fetch(candidate[:model])
        expect(price.values_at("input_per_mtok", "output_per_mtok")).to all(be_a(Numeric).and(be >= 0)), candidate[:model]
      end
      expect(table.fetch(EvalHelpers::CANDIDATES.dig("ollama", :model)).values).to all(eq(0))
    end
  end

  describe "R28: rate limits" do
    it "R28: stops at the first 429, reports the run as cut short and doesn't raise" do
      calls = 0
      adapter = eval_llm do
        calls += 1
        raise Llm::RateLimitError if calls == 4

        nil
      end

      report = nil
      expect { report = score(adapter) }.not_to raise_error

      expect(report[:rate_limited]).to be(true)
      expect(adapter.call_count).to eq(4)
    end

    it "R28: reports rate_limited false for a run that finishes" do
      expect(score(eval_llm)[:rate_limited]).to be(false)
    end
  end
end
