require "rails_helper"

RSpec.describe "Chat::Orchestrator" do
  let(:chat_user_id) { SecureRandom.uuid }

  # R9: the web shows high-stress content only when the chat response carries this trigger, and
  # the API sets it only for the express-distress intent, never at the LLM's discretion.
  describe "R9: the express-distress handler sets the high-stress-intent trigger" do
    it "R9: sets trigger high-stress-intent when the message is classified as express-distress" do
      result = send_chat("I'm so overwhelmed", llm: fake_llm(llm_output("express-distress")))

      expect(result.trigger).to eq(ChatHelpers::HIGH_STRESS_TRIGGER)
    end

    (ChatHelpers::INTENTS - [ "express-distress" ]).each do |intent|
      it "R9: sets no trigger for #{intent}" do
        stub_booker(booker_result(outcome: :not_found, success: false))

        result = send_chat("Hello", llm: fake_llm(llm_output(intent)))

        expect(result.trigger).to be_nil
      end
    end

    it "R9: ignores a trigger the LLM tries to set itself" do
      output = llm_output("ask-question", reply: "high-stress-intent").merge("trigger" => "high-stress-intent")

      result = send_chat("What happens next?", llm: FakeLlmAdapter.new.always_respond_with(output))

      expect(result.trigger).to be_nil
    end

    it "R2, R9: records the distress flag in the assessment draft even if the LLM leaves it out" do
      send_chat("I'm scared, my back pain is getting worse",
        llm: fake_llm(llm_output("express-distress", fields: { "reason" => "Back pain" })))

      send_chat("High urgency, mornings", llm: fake_llm(
        llm_output("provide-details", fields: { "urgency" => "high", "preferred_window" => "Mornings" })
      ))

      expect(saved_assessments(chat_user_id)).to contain_exactly(include("distress" => true))
    end
  end

  # R13 seam: once a user withdraws consent or asks for deletion, chat makes no LLM call.
  # Consent::Ledger belongs to the consent slice and is stubbed here.
  describe "R13: consent is checked before every LLM call" do
    it "R13: asks the ledger about this user before calling the LLM" do
      ledger = stub_consent(false)
      llm = fake_llm(llm_output("ask-question"))

      send_chat("What happens next?", llm: llm)

      expect(ledger).to have_received(:withdrawn?).with(chat_user_id).at_least(:once)
      expect(llm.call_count).to eq(1)
    end

    it "R13: makes no LLM call and raises Chat::ConsentWithdrawn once consent is withdrawn" do
      stub_consent(true)
      llm = FakeLlmAdapter.new.always_respond_with(llm_output("ask-question"))

      expect { send_chat("What happens next?", llm: llm) }.to raise_error(Chat::ConsentWithdrawn)
      expect(llm.call_count).to eq(0)
    end

    it "R13: checks again before the validation retry, and skips it if consent was withdrawn meanwhile" do
      ledger = stub_consent(false, true)
      llm = fake_llm(llm_output("admin-override"), llm_output("ask-question"))

      expect { send_chat("What happens next?", llm: llm) }.to raise_error(Chat::ConsentWithdrawn)
      expect(llm.call_count).to eq(1)
      expect(ledger).to have_received(:withdrawn?).twice
    end

    it "R13: saves nothing from a message sent after consent was withdrawn" do
      stub_consent(true)
      llm = FakeLlmAdapter.new.always_respond_with(llm_output("provide-details", fields: { "reason" => "Back pain" }))

      expect { send_chat("Back pain", llm: llm) }.to raise_error(Chat::ConsentWithdrawn)

      stub_consent(false)
      later = fake_llm(llm_output("ask-question"))
      send_chat("What happens next?", llm: later)
      expect(later.payloads.last.system).not_to include("Back pain")
    end
  end
end
