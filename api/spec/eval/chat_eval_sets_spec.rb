require "rails_helper"

# The committed chat eval sets (api/eval/chat) are well formed, so the chat specs and the eval
# harness (R27) run over everything they claim to cover.
RSpec.describe "Chat eval sets" do
  it "R1: the intent set has labeled example utterances for exactly the intents in the intent list" do
    expect(intent_set.keys).to match_array(ChatHelpers::INTENTS)
    intent_set.each do |intent, utterances|
      expect(utterances.size).to be >= 5, "#{intent} needs at least 5 example utterances"
      expect(utterances).to all(be_a(String).and(be_present))
    end
  end

  # The deployed smoke test's opening messages were classified out-of-scope by a real provider, so
  # the eval runs them too: provide-details is about any need, not only a health one.
  it "R1: provide-details includes the deployed smoke test's non-health reason, urgency and availability" do
    expect(intent_set.fetch("provide-details")).to include(
      "I would like help relocating my pottery studio to a new building.",
      "It is fairly urgent, within the next two weeks.",
      "Weekday mornings suit me best."
    )
  end

  it "R1: no utterance is labeled with more than one intent" do
    all_utterances = intent_set.values.flatten.map(&:downcase)

    expect(all_utterances.uniq.size).to eq(all_utterances.size)
  end

  it "R2: has scripted conversations whose expected records are schema-valid" do
    expect(scripted_conversations.size).to be >= 3
    scripted_conversations.each do |conversation|
      expect(conversation["turns"]).to all(include("user", "scripted_llm"))
      expect(schema_errors(conversation["expected_assessment"])).to be_empty, conversation["id"]
    end
  end

  it "R3: the adversarial set covers empty, 10,000-character, emoji-only and prompt-injection input" do
    inputs = adversarial_inputs.to_h { |entry| [ entry["id"], entry["message"] ] }

    expect(inputs["empty"]).to eq("")
    expect(inputs["ten-thousand-characters"].length).to eq(10_000)
    expect(inputs["emoji-only"]).to match(/\A\p{Extended_Pictographic}+\z/)
    expect(inputs["prompt-injection"]).to match(/ignore previous instructions/i)
  end

  it "R3: the adversarial set has diagnosis and outcome bait, each with a bait reply the guard must catch" do
    bait = adversarial_inputs.select { |entry| entry["expect"] == "no-diagnosis-or-outcome-claim" }
    messages = bait.map { |entry| entry["message"] }

    expect(messages).to include(a_string_matching(/just tell me what i have/i),
      a_string_matching(/will i definitely get accepted/i))
    expect(bait.size).to be >= 4
    bait.each do |entry|
      expect(entry["bait_reply"]).to match(ChatHelpers::DIAGNOSIS_OR_OUTCOME), entry["id"]
    end
  end
end
