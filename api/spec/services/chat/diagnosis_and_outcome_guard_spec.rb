require "rails_helper"

# R3 [gotcha]: the chatbot never claims a diagnosis or outcome that isn't backed by stored data.
# LLM reply text that diagnoses the user, or promises an outcome, approval or eligibility, is
# swapped for the handler's safe template on every intent whose handler uses the LLM's text.
RSpec.describe "Chat::Orchestrator diagnosis and outcome guard" do
  let(:chat_user_id) { SecureRandom.uuid }

  diagnosis_claims = [
    "It sounds like you have depression.",
    "You have a herniated disc.",
    "This is clearly an anxiety disorder.",
    "You're probably suffering from PTSD.",
    "Based on what you said, you likely have insomnia."
  ]
  outcome_claims = [
    "Yes, you'll be approved.",
    "You will definitely get accepted.",
    "Don't worry, this will fix it.",
    "You're eligible!",
    "Therapy is guaranteed to work.",
    "You qualify for support."
  ]
  # Intents whose handlers may use the LLM's own text. Every one is guarded.
  free_text_intents = %w[ask-question provide-details express-distress]

  def expect_guarded(reply, claim)
    expect(reply).to be_present
    expect(reply).not_to include(claim)
    expect(reply).not_to match(ChatHelpers::DIAGNOSIS_OR_OUTCOME)
  end

  describe "R3: diagnosis claims" do
    diagnosis_claims.each do |claim|
      it "R3: swaps out \"#{claim}\" for a safe template" do
        result = send_chat("Just tell me what I have.", llm: fake_llm(llm_output("ask-question", reply: claim)))

        expect_guarded(result.reply, claim)
      end

      it "R3: Chat::ReplyGuard reports \"#{claim}\" as an unbacked claim" do
        expect(Chat::ReplyGuard.unbacked_claim?(claim)).to be(true)
      end
    end
  end

  describe "R3: outcome, approval and eligibility promises" do
    outcome_claims.each do |claim|
      it "R3: swaps out \"#{claim}\" for a safe template" do
        result = send_chat("Will I definitely get accepted?", llm: fake_llm(llm_output("ask-question", reply: claim)))

        expect_guarded(result.reply, claim)
      end

      it "R3: Chat::ReplyGuard reports \"#{claim}\" as an unbacked claim" do
        expect(Chat::ReplyGuard.unbacked_claim?(claim)).to be(true)
      end
    end
  end

  describe "R3: on every intent's free-text reply" do
    free_text_intents.each do |intent|
      it "R3: guards a #{intent} reply that diagnoses" do
        claim = "It sounds like you have depression, and therapy will fix it."

        result = send_chat("I feel low all the time. What do I have?", llm: fake_llm(llm_output(intent, reply: claim)))

        expect(result.intent).to eq(intent)
        expect_guarded(result.reply, claim)
      end
    end

    it "R3: stores the guarded reply, not the claim, in the conversation" do
      claim = "You have a herniated disc."

      send_chat("What's wrong with my back?", llm: fake_llm(llm_output("ask-question", reply: claim)))

      contents = Conversation.for_user(chat_user_id).messages.where(role: "assistant").map(&:content)
      expect(contents).to all(be_present)
      expect(contents).not_to include(a_string_including(claim))
    end
  end

  describe "R3: replies with no diagnosis or promise pass through unchanged" do
    [
      "Do you have a preferred window for appointments?",
      "I can't diagnose anything or promise an outcome, but a clinician can talk it through with you.",
      "A clinician will go over your options with you.",
      "How long have you had trouble sleeping?"
    ].each do |reply|
      it "R3: keeps \"#{reply}\"" do
        result = send_chat("Can you help?", llm: fake_llm(llm_output("ask-question", reply: reply)))

        expect(result.reply).to eq(reply)
      end
    end
  end

  describe "R3, R27: the committed diagnosis and outcome bait" do
    ChatHelpers.adversarial_inputs.select { |input| input["bait_reply"] }.each do |input|
      it "R3: #{input['id']} gets a guarded reply when the LLM takes the bait" do
        result = send_chat(input["message"], llm: fake_llm(llm_output("ask-question", reply: input["bait_reply"])))

        expect_guarded(result.reply, input["bait_reply"])
      end
    end
  end
end
