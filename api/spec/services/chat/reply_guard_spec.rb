require "rails_helper"

# R3 [gotcha]: the chatbot never claims a booking, time or outcome that isn't backed by stored
# data. Booking and time statements come only from Scheduling::Booker's structured result; a final
# guard swaps out any LLM reply that states a date, time or booking the handler result doesn't back.
RSpec.describe "Chat::Orchestrator reply guard" do
  let(:chat_user_id) { SecureRandom.uuid }
  let(:booking_id) { SecureRandom.uuid }
  let(:new_slot) { { id: SecureRandom.uuid, starts_at: "2030-03-05T14:30:00Z", ends_at: "2030-03-05T15:00:00Z" } }
  let(:old_slot) { { id: SecureRandom.uuid, starts_at: "2030-03-04T09:00:00Z", ends_at: "2030-03-04T09:30:00Z" } }

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

  describe "R3, R36: request-reschedule replies come from Scheduling::Booker's result" do
    it "R36: calls Scheduling::Booker for the user with the chosen booking and slot" do
      booker_class, booker = stub_booker(booker_result(outcome: :rescheduled, success: true, slot: new_slot,
        previous_slot: old_slot, booking_id: booking_id))

      send_chat("Move me to that slot please", llm: fake_llm(llm_output("request-reschedule")),
        booking_id: booking_id, slot_id: new_slot[:id])

      expect(booker_class).to have_received(:new).with(user_id: chat_user_id)
      expect(booker).to have_received(:reschedule).with(booking_id: booking_id, slot_id: new_slot[:id])
    end

    it "R36: on success, returns the booker's structured result and a reply that reflects it" do
      result_data = booker_result(outcome: :rescheduled, success: true, slot: new_slot, previous_slot: old_slot,
        booking_id: booking_id)
      stub_booker(result_data)

      result = send_chat("Move me to that slot please",
        llm: fake_llm(llm_output("request-reschedule", reply: "Done! See you Friday at 3pm.")),
        booking_id: booking_id, slot_id: new_slot[:id])

      expect(result.scheduling).to eq(result_data.to_h)
      expect(result.reply).to match(/moved|rescheduled|changed/i)
      expect(result.reply).not_to match(/friday|3\s*pm/i)
    end

    it "R3: when the slot is taken, says so and never claims the move happened" do
      stub_booker(booker_result(outcome: :slot_taken, success: false, slot: new_slot))

      result = send_chat("Move me to that slot please",
        llm: fake_llm(llm_output("request-reschedule", reply: "All done, you're booked for Tuesday at 2:30pm!")),
        booking_id: booking_id, slot_id: new_slot[:id])

      expect(result.scheduling).to include(outcome: "slot_taken")
      expect(result.reply).to match(/taken|no longer available|not available|isn't available/i)
      expect(result.reply).not_to match(ChatHelpers::BOOKING_CLAIM)
      expect(result.reply).not_to match(/all done/i)
    end

    it "R3: when the booking isn't found, says so and never claims the move happened" do
      stub_booker(booker_result(outcome: :not_found, success: false))

      result = send_chat("Move me to that slot please",
        llm: fake_llm(llm_output("request-reschedule", reply: "Rescheduled! See you Monday.")),
        booking_id: booking_id, slot_id: new_slot[:id])

      expect(result.scheduling).to include(outcome: "not_found")
      expect(result.reply).not_to match(ChatHelpers::BOOKING_CLAIM)
      expect(result.reply).not_to match(/rescheduled!|monday/i)
    end
  end
end
