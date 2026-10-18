require "rails_helper"

# Regressions from the deployed smoke test on claude-haiku-4-5. The Anthropic Messages API is
# stubbed with response bodies in the exact shape Haiku returns for a forced tool call, so the real
# adapter, client and orchestrator run end to end. Two failures were seen: on-topic messages about a
# non-health need were classified out-of-scope (R1), and Haiku filled a missing field with the
# placeholder "<UNKNOWN>", which was saved as the assessment's reason (R2).
RSpec.describe "Chat::Orchestrator with Anthropic tool use" do
  let(:chat_user_id) { SecureRandom.uuid }
  let(:client) { Llm::Client.new(primary: Llm::Adapters::Anthropic.new(api_key: "test-claude-key", model: "claude-haiku-4-5")) }

  # A Messages API body as Haiku sends it when tool_choice forces the respond tool: one tool_use
  # block and no text block.
  def haiku_body(intent:, fields: {}, reply: "Thanks, noted.")
    {
      model: "claude-haiku-4-5-20251001", id: "msg_test", type: "message", role: "assistant",
      content: [ { type: "tool_use", id: "toolu_test", name: "respond", caller: { type: "direct" },
                   input: { intent: intent, assessment_fields: fields, reply: reply } } ],
      container: nil, stop_reason: "tool_use", stop_sequence: nil, stop_details: nil,
      usage: { input_tokens: 1481, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 101,
               service_tier: "standard" },
      diagnostics: nil
    }.to_json
  end

  def stub_haiku(*answers)
    stub_request(:post, LlmHelpers::ANTHROPIC_URL)
      .to_return(*answers.map { |answer| { status: 200, body: haiku_body(**answer), headers: { "Content-Type" => "application/json" } } })
  end

  def chat(message)
    Chat::Orchestrator.new(user_id: chat_user_id, llm_client: client).handle(message: message)
  end

  def draft
    Conversation.for_user(chat_user_id).reload.draft
  end

  describe "R1: on-topic messages route to provide-details" do
    it "routes a Haiku tool-use answer for a non-health reason to provide-details, not the out-of-scope template" do
      stub_haiku({ intent: "provide-details", fields: { reason: "Relocating a pottery studio to a new building" },
                   reply: "Thanks for sharing that. How urgent does this feel: low, medium or high?" })

      result = chat("I would like help relocating my pottery studio to a new building.")

      expect(result.intent).to eq("provide-details")
      expect(result.reply).not_to eq(Chat::Handlers::OutOfScope::REPLY)
      expect(result.actions).to be_empty
      expect(draft).to include("reason" => "Relocating a pottery studio to a new building")
    end

    it "tells the model that any reason, whatever its subject, counts as provide-details" do
      stub_haiku({ intent: "provide-details" })

      chat("I would like help relocating my pottery studio to a new building.")

      expect(a_request(:post, LlmHelpers::ANTHROPIC_URL).with { |request|
        system = JSON.parse(request.body).fetch("system")
        system.match?(/whatever (?:its|the) subject/i) && system.match?(/out-of-scope:[^\n]*unrelated to onboarding/i)
      }).to have_been_made.once
    end

    it "tells the model that answers to its own question, such as urgency, availability or a yes, count as provide-details" do
      expect(Chat::Prompt.system).to match(/urgency.*availability|availability.*urgency/im)
        .and match(/- provide-details:(?:(?!\n- ).)*\b(?:yes|confirmation)\b/m)
    end
  end

  describe "R2: placeholder and sentinel values are never saved" do
    it "drops a <UNKNOWN> reason from Haiku, leaves the reason missing and saves no assessment" do
      stub_haiku(
        { intent: "provide-details", fields: { urgency: "high" } },
        { intent: "provide-details", fields: { preferred_window: "weekday mornings" } },
        { intent: "provide-details", fields: { reason: "<UNKNOWN>", distress: false } }
      )

      chat("It is fairly urgent, within the next two weeks.")
      chat("Weekday mornings suit me best.")
      result = chat("Yes, please go ahead.")

      expect(result.assessment).to be_nil
      expect(Assessment.where(user_id: chat_user_id)).not_to exist
      expect(draft).not_to have_key("reason")
      expect(draft).to include("urgency" => "high", "preferred_window" => "weekday mornings")
    end

    it "does not complete an assessment from a draft that already holds a placeholder, and clears it" do
      Conversation.for_user(chat_user_id).update!(assessment_draft: { "reason" => "<UNKNOWN>", "urgency" => "high" })
      stub_haiku({ intent: "provide-details", fields: { preferred_window: "weekday mornings" } })

      result = chat("Weekday mornings suit me best.")

      expect(result.assessment).to be_nil
      expect(Assessment.where(user_id: chat_user_id)).not_to exist
      expect(draft).to eq("urgency" => "high", "preferred_window" => "weekday mornings")
    end

    it "completes the assessment once a real reason arrives" do
      stub_haiku(
        { intent: "provide-details", fields: { urgency: "high", preferred_window: "weekday mornings", reason: "<UNKNOWN>" } },
        { intent: "provide-details", fields: { reason: "Relocating a pottery studio" } }
      )

      expect(chat("Urgent, and weekday mornings suit me.").assessment).to be_nil
      result = chat("I need help relocating my pottery studio.")

      expect(result.assessment).to include("reason" => "Relocating a pottery studio", "urgency" => "high")
    end

    [
      "<UNKNOWN>", "<NAME>", "[NAME]", "[DATE_OF_BIRTH]", "<ADDRESS>", "[REDACTED]", "<reason>",
      "unknown", "Unknown.", "N/A", "n/a", "none", "None provided", "null", "nil", "undefined", "TBD",
      "not provided", "Not specified", "not stated", "unspecified", "-", "?", "...",
      "Help for <NAME> with a move", "[NAME] wants to relocate"
    ].each do |value|
      it "treats #{value.inspect} as not provided" do
        output, errors = Chat::ResponseValidator.call(
          "intent" => "provide-details", "reply" => "Thanks.",
          "assessment_fields" => { "reason" => value, "preferred_window" => value, "notes" => value }
        )

        expect(errors).to be_nil
        expect(output.fields).to eq({})
      end
    end

    it "keeps ordinary values that only resemble a sentinel" do
      fields = { "reason" => "Unknown pain in my knee", "preferred_window" => "Any time, none of the weekends",
                 "notes" => "Prefers <3 short sessions" }

      output, = Chat::ResponseValidator.call("intent" => "provide-details", "reply" => "Thanks.", "assessment_fields" => fields)

      expect(output.fields).to eq(fields)
    end

    it "refuses to save an Assessment whose data holds a placeholder" do
      data = { "reason" => "<UNKNOWN>", "urgency" => "high", "preferred_window" => "weekday mornings",
               "distress" => false, "notes" => "" }

      assessment = Assessment.new(user_id: chat_user_id, data: data, schema_version: Chat::AssessmentSchema.version)

      expect(assessment).not_to be_valid
    end
  end
end
