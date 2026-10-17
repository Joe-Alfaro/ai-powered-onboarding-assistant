require "rails_helper"

# R36 through the chatbot, end to end over POST /chat/messages with real slots, bookings and
# Scheduling::Booker; only the LLM is a FakeLlmAdapter. A reschedule or cancel request finds the
# user's active booking from the token (R19) and answers with structured `choices`; the web sends
# the chosen one back (`booking_id` and `slot_id`, or `booking_id` and `cancel: true`) and the
# reply comes from Booker's real result (R3). Times stay ISO-8601 UTC in `choices` and
# `scheduling`, for the web to show in the user's zone (R37).
RSpec.describe "Chat reschedule and cancel actions", type: :request do
  let(:chat_user_id) { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let(:headers) { auth_headers(chat_user_id) }
  # An LLM that routes every message to request-reschedule and tries to claim the move itself.
  let(:llm) { FakeLlmAdapter.new.always_respond_with(llm_output("request-reschedule", reply: "Done, I've moved you to Friday at 3pm!")) }

  let(:current_slot) { create_slot(starts_at: 2.days.from_now.utc.change(hour: 9, min: 0, sec: 0)) }
  let!(:booking) { create_booking(user_id: chat_user_id, slot: current_slot) }
  let!(:sooner_slot) { create_slot(starts_at: 3.days.from_now.utc.change(hour: 10, min: 0, sec: 0)) }
  let!(:later_slot) { create_slot(starts_at: 4.days.from_now.utc.change(hour: 14, min: 30, sec: 0)) }

  before { allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: llm)) }

  def post_message(message, headers: self.headers, **extra)
    post "/chat/messages", params: { message: message, **extra }, headers: headers, as: :json
  end

  def body
    response.parsed_body
  end

  def offered_slot_ids
    body["choices"].map { |choice| choice.dig("slot", "id") }
  end

  def expect_no_claim_in_reply
    expect(body["reply"]).to be_present
    expect(body["reply"]).not_to match(ChatHelpers::BOOKING_CLAIM)
    expect(body["reply"]).not_to match(ChatHelpers::DATE_OR_TIME)
    expect(body["reply"]).not_to include("Friday")
  end

  # The truthful "you have no booking" answer, which never invents one.
  let(:no_booking) do
    /(?:don't|do\s+not|doesn't|does\s+not|couldn't|could\s+not|can't|cannot)\s+(?:have|see|find)\s+(?:an?\s+|any\s+)?(?:upcoming\s+|active\s+|current\s+)?(?:appointment|booking)|\bno\s+(?:upcoming\s+|active\s+|current\s+)?(?:appointment|booking)/ix
  end

  describe "R36: asking to reschedule" do
    it "R36, R3: with no active booking, says so truthfully and offers no choices" do
      booking.update!(status: "cancelled")
      create_booking(user_id: other_user_id, slot: create_slot(starts_at: 5.days.from_now.utc.change(min: 0, sec: 0)))

      post_message("Can I move my appointment?")

      expect(response).to have_http_status(:ok)
      expect(body["reply"]).to match(no_booking)
      expect_no_claim_in_reply
      expect(body["choices"]).to eq([])
      expect(body["scheduling"]).to be_nil
    end

    it "R36, R19: finds the user's active booking from the token and offers open future slots as choices" do
      past_slot = create_slot(starts_at: 2.days.ago.utc.change(min: 0, sec: 0))
      taken_slot = create_slot(starts_at: 3.days.from_now.utc.change(hour: 12, min: 0, sec: 0))
      create_booking(user_id: other_user_id, slot: taken_slot)

      post_message("Can I move my appointment?")

      expect(response).to have_http_status(:ok)
      expect(body["choices"]).to eq([ slot_choice(booking, sooner_slot), slot_choice(booking, later_slot) ])
      expect(offered_slot_ids).not_to include(current_slot.id, past_slot.id, taken_slot.id)
      expect(body["choices"].map { |choice| choice.dig("slot", "starts_at") }).to all(match(SchedulingHelpers::ISO_8601_UTC))
      expect_no_claim_in_reply
      expect(booking.reload.slot_id).to eq(current_slot.id)
    end

    it "R36: offers at most five open slots, soonest first" do
      extra = (5..9).map { |day| create_slot(starts_at: day.days.from_now.utc.change(hour: 11, min: 0, sec: 0)) }

      post_message("I need to reschedule")

      expect(offered_slot_ids).to eq([ sooner_slot, later_slot, *extra.first(3) ].map(&:id))
    end

    it "R36, R3: with a booking but no other open slot, says no other time is open and offers no choices" do
      sooner_slot.destroy!
      later_slot.destroy!

      post_message("Can I move my appointment?")

      expect(body["reply"]).to match(/no\s+other\s+(?:open\s+)?(?:times?|slots?)|no\s+(?:open|available)\s+(?:times?|slots?)|nothing\s+else\s+(?:is\s+)?(?:open|available)/i)
      expect_no_claim_in_reply
      expect(body["choices"]).to eq([])
      expect(booking.reload.slot_id).to eq(current_slot.id)
    end
  end

  describe "R36: choosing a slot" do
    it "R36: reschedules through Scheduling::Booker, frees the old slot and returns the new time from its result" do
      allow(Scheduling::Booker).to receive(:new).and_call_original

      post_message("Choose this time", booking_id: booking.id, slot_id: later_slot.id)

      expect(response).to have_http_status(:ok)
      expect(Scheduling::Booker).to have_received(:new).with(user_id: chat_user_id)
      expect(booking.reload.slot_id).to eq(later_slot.id)
      expect(active_bookings_on(current_slot)).to be_empty
      expect(Slot.open).to include(current_slot)
      expect(body["scheduling"]).to include("outcome" => "rescheduled", "booking_id" => booking.id,
        "slot" => later_slot.summary.stringify_keys, "previous_slot" => current_slot.summary.stringify_keys)
      expect(body["reply"]).to match(/moved|rescheduled/i)
      expect(body["reply"]).not_to match(ChatHelpers::DATE_OR_TIME)
      expect(body["choices"]).to eq([])
    end

    it "R36, R16: a choice needs no LLM call, so it works while the LLM is down" do
      down = FakeLlmAdapter.new.fail_with(Llm::ServerError).fail_with(Llm::ServerError)
      allow(Llm::Client).to receive(:from_env).and_return(Llm::Client.new(primary: down))

      post_message("Choose this time", booking_id: booking.id, slot_id: sooner_slot.id)

      expect(response).to have_http_status(:ok)
      expect(body["scheduling"]).to include("outcome" => "rescheduled")
      expect(booking.reload.slot_id).to eq(sooner_slot.id)
      expect(down.call_count).to eq(0)
    end

    it "R36, R3: a slot taken in between gets a truthful reply and fresh choices, and nothing moves" do
      post_message("Can I move my appointment?")
      expect(offered_slot_ids).to include(sooner_slot.id)
      create_booking(user_id: other_user_id, slot: sooner_slot)

      post_message("Choose this time", booking_id: booking.id, slot_id: sooner_slot.id)

      expect(response).to have_http_status(:ok)
      expect(body["scheduling"]).to include("outcome" => "slot_taken")
      expect(body["reply"]).to match(/no\s+longer\s+available|already\s+(?:been\s+)?(?:taken|booked)|isn't\s+available|not\s+available/i)
      expect(body["reply"]).not_to match(/moved|rescheduled/i)
      expect_no_claim_in_reply
      expect(body["choices"]).to eq([ slot_choice(booking, later_slot) ])
      expect(booking.reload.slot_id).to eq(current_slot.id)
      expect(active_bookings_on(sooner_slot).pluck(:user_id)).to eq([ other_user_id ])
    end

    it "R19: another user's booking_id changes nothing for either user" do
      other_slot = create_slot(starts_at: 6.days.from_now.utc.change(hour: 8, min: 0, sec: 0))
      other_booking = create_booking(user_id: other_user_id, slot: other_slot)

      post_message("Choose this time", booking_id: other_booking.id, slot_id: later_slot.id)

      expect(response).to have_http_status(:ok)
      expect(other_booking.reload).to have_attributes(slot_id: other_slot.id, status: "active")
      expect(booking.reload.slot_id).to eq(current_slot.id)
      expect(Slot.open).to include(later_slot)
      expect(body["reply"]).not_to match(/moved|rescheduled/i)
      expect_no_claim_in_reply
      expect(response.body).not_to include(other_slot.id)
    end

    it "R36, R3: a slot that isn't open, such as one in the past, is refused and nothing moves" do
      past_slot = create_slot(starts_at: 1.day.ago.utc.change(min: 0, sec: 0))

      post_message("Choose this time", booking_id: booking.id, slot_id: past_slot.id)

      expect(response).to have_http_status(:ok)
      expect(booking.reload.slot_id).to eq(current_slot.id)
      expect(body.dig("scheduling", "outcome")).not_to eq("rescheduled")
      expect(body["reply"]).not_to match(/moved|rescheduled/i)
      expect_no_claim_in_reply
    end
  end

  describe "R36: cancelling" do
    let(:llm) { FakeLlmAdapter.new.always_respond_with(llm_output("request-reschedule", reply: "I've cancelled it for you.")) }

    it "R36, R3: a cancel request asks for confirmation with a confirm choice and changes nothing yet" do
      post_message("Please cancel my appointment")

      expect(response).to have_http_status(:ok)
      expect(body["choices"]).to eq([ confirm_cancel_choice(booking) ])
      expect(body["reply"]).to match(/cancel/i)
      expect(body["reply"]).not_to match(/cancell?ed/i)
      expect_no_claim_in_reply
      expect(body["scheduling"]).to be_nil
      expect(booking.reload.status).to eq("active")
    end

    it "R36: confirming cancels through Scheduling::Booker, says so truthfully and opens the old slot again" do
      allow(Scheduling::Booker).to receive(:new).and_call_original

      post_message("Yes, cancel it", booking_id: booking.id, cancel: true)

      expect(response).to have_http_status(:ok)
      expect(Scheduling::Booker).to have_received(:new).with(user_id: chat_user_id)
      expect(booking.reload.status).to eq("cancelled")
      expect(active_bookings_on(current_slot)).to be_empty
      expect(Slot.open).to include(current_slot)
      expect(body["scheduling"]).to include("outcome" => "cancelled", "booking_id" => booking.id,
        "previous_slot" => current_slot.summary.stringify_keys)
      expect(body["reply"]).to match(/cancell?ed/i)
      expect(body["reply"]).not_to match(ChatHelpers::DATE_OR_TIME)
      expect(body["choices"]).to eq([])
      expect(llm.call_count).to eq(0)
    end

    it "R36, R3: confirming an already cancelled booking says nothing was changed" do
      booking.update!(status: "cancelled")

      post_message("Yes, cancel it", booking_id: booking.id, cancel: true)

      expect(body.dig("scheduling", "outcome")).to eq("not_found")
      expect(body["reply"]).not_to match(/has\s+been\s+cancell?ed|is\s+cancell?ed|I(?:'ve|\s+have)\s+cancell?ed/i)
      expect_no_claim_in_reply
    end

    it "R19: confirming with another user's booking_id cancels nothing" do
      other_booking = create_booking(user_id: other_user_id, slot: sooner_slot)

      post_message("Yes, cancel it", booking_id: other_booking.id, cancel: true)

      expect(response).to have_http_status(:ok)
      expect(other_booking.reload.status).to eq("active")
      expect(booking.reload.status).to eq("active")
      expect(body["reply"]).not_to match(/cancell?ed/i)
      expect_no_claim_in_reply
    end

    it "R36, R3: with no active booking, a cancel request says so and offers no choices" do
      booking.update!(status: "cancelled")

      post_message("Please cancel my appointment")

      expect(body["reply"]).to match(no_booking)
      expect_no_claim_in_reply
      expect(body["choices"]).to eq([])
    end
  end
end
