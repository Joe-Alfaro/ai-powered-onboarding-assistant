require "rails_helper"

# R1: for each intent in the intent list, the chatbot routes every labeled utterance in the
# committed intent set to the handler for that intent. The LLM is scripted to classify each one
# correctly; whether real providers classify them correctly is the eval harness's job (R27).
#
# Described by name so a missing class fails each example instead of stopping the suite at load.
RSpec.describe "Chat::Orchestrator routing" do
  let(:chat_user_id) { SecureRandom.uuid }

  before { stub_booker(booker_result(outcome: :not_found, success: false)) }

  def spy_on_handlers
    ChatHelpers::HANDLERS.transform_values do |name|
      handler = name.constantize
      allow(handler).to receive(:new).and_call_original
      handler
    end
  end

  it "R1: maps each intent in the intent list to its Chat::Handlers class" do
    handlers = spy_on_handlers

    expect(handlers.keys).to match_array(ChatHelpers::INTENTS)
  end

  ChatHelpers::INTENTS.each do |intent|
    it "R1: routes every labeled #{intent} utterance to #{ChatHelpers::HANDLERS[intent]} and no other handler" do
      handlers = spy_on_handlers
      utterances = intent_set.fetch(intent)

      utterances.each do |utterance|
        result = send_chat(utterance, llm: fake_llm(llm_output(intent)))

        expect(result.intent).to eq(intent)
        expect(result.reply).to be_a(String).and(be_present)
      end

      expect(handlers.fetch(intent)).to have_received(:new).exactly(utterances.size).times
      handlers.except(intent).each_value { |other| expect(other).not_to have_received(:new) }
    end
  end

  it "R1: sends the user's message to the LLM as the latest user turn" do
    llm = fake_llm(llm_output("ask-question"))

    send_chat("What happens after I finish signing up?", llm: llm)

    expect(user_turns(llm).last[:content]).to eq("What happens after I finish signing up?")
  end

  it "R1: asks the LLM for one of the listed intents and the assessment schema's fields" do
    llm = fake_llm(llm_output("ask-question"))

    send_chat("Hello", llm: llm)

    response_schema = llm.payloads.first.response_schema.deep_stringify_keys
    expect(response_schema.dig("properties", "intent", "enum")).to match_array(ChatHelpers::INTENTS)
    expect(response_schema.dig("properties", "assessment_fields", "properties").keys)
      .to match_array(assessment_schema.fetch("properties").keys)
  end
end
