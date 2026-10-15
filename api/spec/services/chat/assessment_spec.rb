require "rails_helper"

# R2: the chatbot produces a structured assessment that validates against the committed schema,
# never saves unvalidated LLM output, and returns the saved record as a summary.
RSpec.describe "Chat::Orchestrator assessment" do
  let(:chat_user_id) { SecureRandom.uuid }

  def run_conversation(conversation)
    conversation["turns"].map do |turn|
      send_chat(turn["user"], llm: fake_llm(turn["scripted_llm"]))
    end
  end

  # The draft the orchestrator sends to the LLM, read back from the system prompt where
  # Llm::PayloadBuilder puts it.
  def draft_sent(adapter)
    adapter.payloads.last.system[/Current assessment draft \(JSON\): (\{.*\})/, 1]&.then { |json| JSON.parse(json) } || {}
  end

  describe "R2: each committed scripted conversation produces a schema-valid record" do
    ChatHelpers.eval_set("conversations").each do |conversation|
      it "R2: #{conversation['id']} saves a record that validates with every required field populated" do
        run_conversation(conversation)

        records = saved_assessments(chat_user_id)
        expect(records.size).to eq(1)
        expect(schema_errors(records.first)).to be_empty
        expect(records.first).to eq(conversation["expected_assessment"])
      end

      it "R2: #{conversation['id']} returns the saved record as a summary on the final turn only" do
        results = run_conversation(conversation)

        expect(results[0...-1].map(&:assessment)).to all(be_nil)
        expect(JSON.parse(results.last.assessment.to_json)).to include(conversation["expected_assessment"])
      end
    end
  end

  it "R2: stores the schema version with the record" do
    run_conversation(scripted_conversations.first)

    expect(Assessment.find_by!(user_id: chat_user_id).schema_version).to be_present
  end

  it "R2: carries validated fields from earlier messages into the draft sent with later ones" do
    send_chat("I can't sleep", llm: fake_llm(llm_output("provide-details", fields: { "reason" => "Can't sleep" })))
    llm = fake_llm(llm_output("ask-question"))

    send_chat("What happens next?", llm: llm)

    expect(draft_sent(llm)).to include("reason" => "Can't sleep")
  end

  it "R2: keeps each user's draft separate" do
    send_chat("I can't sleep", llm: fake_llm(llm_output("provide-details", fields: { "reason" => "Can't sleep" })))
    llm = fake_llm(llm_output("ask-question"))

    send_chat("What happens next?", llm: llm, user_id: SecureRandom.uuid)

    expect(draft_sent(llm)).not_to include("reason")
  end

  describe "R2 [gotcha]: malformed or missing-field LLM output is validated and retried once" do
    valid = { "intent" => "provide-details", "assessment_fields" => { "reason" => "Back pain" }, "reply" => "Thanks." }

    {
      "an intent outside the intent list" => valid.merge("intent" => "admin-override"),
      "a missing intent" => valid.except("intent"),
      "a missing reply" => valid.except("reply"),
      "a non-text reply" => valid.merge("reply" => { "text" => "Thanks." }),
      "missing assessment_fields" => valid.except("assessment_fields"),
      "an urgency outside the schema" => valid.merge("assessment_fields" => { "urgency" => "whenever" }),
      "a distress flag that isn't a boolean" => valid.merge("assessment_fields" => { "distress" => "yes" }),
      "assessment_fields that aren't an object" => valid.merge("assessment_fields" => "Back pain")
    }.each do |description, malformed|
      it "R2: retries once after #{description}, then uses the valid answer" do
        llm = fake_llm(malformed, valid)

        result = send_chat("My back hurts", llm: llm)

        expect(llm.call_count).to eq(2)
        expect(result.intent).to eq("provide-details")
        expect(result.reply).to eq("Thanks.")
      end
    end

    it "R2: retries once when the adapter can't read the provider's output" do
      llm = FakeLlmAdapter.new.fail_with(Llm::InvalidResponseError).respond_with(valid)

      result = send_chat("My back hurts", llm: llm)

      expect(llm.call_count).to eq(2)
      expect(result.intent).to eq("provide-details")
    end

    it "R2: after a second malformed answer, falls back to the out-of-scope reply with a continue manually action" do
      redirect = send_chat("Write me a poem", llm: fake_llm(llm_output("out-of-scope", reply: "Roses are red")))
      llm = fake_llm(valid.merge("intent" => "admin-override"), valid.except("reply"))

      result = send_chat("My back hurts", llm: llm)

      expect(llm.call_count).to eq(2)
      expect(result.reply).to eq(redirect.reply)
      expect(result.actions).to include("continue_manually")
    end

    it "R2: never makes a third call" do
      llm = FakeLlmAdapter.new.always_respond_with(valid.merge("intent" => "admin-override"))

      send_chat("My back hurts", llm: llm)

      expect(llm.call_count).to eq(2)
    end
  end

  describe "R2 [gotcha]: invalid output never reaches the database" do
    let(:almost_done) { { "reason" => "Back pain", "preferred_window" => "Mornings" } }
    let(:bad_urgency) { llm_output("provide-details", fields: { "urgency" => "whenever" }) }

    before { send_chat("Back pain, mornings please", llm: fake_llm(llm_output("provide-details", fields: almost_done))) }

    it "R2: saves no assessment when the completing answer is invalid twice" do
      result = send_chat("Whenever is fine", llm: fake_llm(bad_urgency, bad_urgency))

      expect(result.assessment).to be_nil
      expect(Assessment.where(user_id: chat_user_id)).to be_empty
    end

    it "R2: keeps the invalid value out of the draft, so a later valid answer saves a valid record" do
      send_chat("Whenever is fine", llm: fake_llm(bad_urgency, bad_urgency))
      llm = fake_llm(llm_output("provide-details", fields: { "urgency" => "low" }))

      result = send_chat("Low urgency", llm: llm)

      expect(draft_sent(llm).to_json).not_to include("whenever")
      expect(result.assessment).to be_present
      expect(saved_assessments(chat_user_id)).to contain_exactly(include("urgency" => "low"))
      expect(schema_errors(saved_assessments(chat_user_id).first)).to be_empty
    end

    it "R2: drops fields the schema doesn't define instead of saving them" do
      llm = fake_llm(llm_output("provide-details", fields: { "urgency" => "low" }).tap do |output|
        output["assessment_fields"]["email"] = "someone@example.test"
      end, llm_output("provide-details", fields: { "urgency" => "low" }))

      send_chat("Low urgency, email me at someone@example.test", llm: llm)

      expect(saved_assessments(chat_user_id).to_json).not_to include("someone@example.test")
      expect(saved_assessments(chat_user_id)).to all(satisfy { |record| schema_errors(record).empty? })
    end
  end
end
