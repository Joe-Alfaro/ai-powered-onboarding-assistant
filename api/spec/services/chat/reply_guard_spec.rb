require "rails_helper"

# R3 [gotcha]: the chatbot never claims a booking, time or outcome that isn't backed by stored
# data. Booking and time statements come only from Scheduling::Booker's structured result; a final
# guard swaps out any LLM reply that states a date, time or booking the handler result doesn't back.
# Replies built from Booker's real result are covered end to end in spec/requests/chat_actions_spec.rb.
RSpec.describe "Chat::Orchestrator reply guard" do
  let(:chat_user_id) { SecureRandom.uuid }

  describe "R3: LLM replies with no handler result behind them" do
    let!(:booker) { stub_booker(booker_result(outcome: :not_found, success: false)).last }

    [
      "You're booked for Friday at 3pm.",
      "See you tomorrow at 10:30!",
      "Your appointment is on March 5th.",
      "We have you down for 2030-03-05.",
      "I've scheduled you for 5/3 at 9am.",
      "Your appointment is confirmed."
    ].each do |claim|
      it "R3: swaps out \"#{claim}\" when nothing was booked" do
        result = send_chat("Am I all set?", llm: fake_llm(llm_output("ask-question", reply: claim)))

        expect(result.reply).to be_present
        expect(result.reply).not_to include(claim)
        expect(result.reply).not_to match(ChatHelpers::DATE_OR_TIME)
        expect(result.reply).not_to match(ChatHelpers::BOOKING_CLAIM)
      end
    end

    it "R3: passes through a reply that states no date, time or booking" do
      reply = "You can upload a photo of your ID next, or type your details in."

      result = send_chat("What's next?", llm: fake_llm(llm_output("ask-question", reply: reply)))

      expect(result.reply).to eq(reply)
    end

    it "R3: answers \"you booked me for Friday, right?\" without confirming it" do
      llm = fake_llm(llm_output("ask-question", reply: "Yes, you're booked for Friday at 3pm."))

      result = send_chat("You booked me for Friday at 3pm, right?", llm: llm)

      expect(result.reply).not_to match(ChatHelpers::DATE_OR_TIME)
      expect(result.reply).not_to match(ChatHelpers::BOOKING_CLAIM)
      expect(result.scheduling).to be_nil
    end

    it "R3: a reschedule request without a chosen booking and slot calls no booker and claims nothing" do
      llm = fake_llm(llm_output("request-reschedule", reply: "Moved you to Monday at 9am."))

      result = send_chat("Can I move my appointment?", llm: llm)

      expect(booker).not_to have_received(:reschedule)
      expect(result.reply).to be_present
      expect(result.reply).not_to match(ChatHelpers::DATE_OR_TIME)
      expect(result.reply).not_to match(ChatHelpers::BOOKING_CLAIM)
    end
  end
end
