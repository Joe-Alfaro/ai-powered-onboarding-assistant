require "rails_helper"

RSpec.describe "Bookings API", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let(:headers) { auth_headers(user_id) }

  def open_slot_ids
    get "/slots", headers: headers
    response.parsed_body["slots"].map { |slot| slot["id"] }
  end

  def error_code
    response.parsed_body.dig("error", "code")
  end

  describe "POST /bookings (R6)" do
    let(:slot) { create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0), length: 30.minutes) }

    it "R6: booking a slot returns a confirmation with the slot's date and time" do
      post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      booking = response.parsed_body["booking"]
      expect(booking).to include("id" => be_present, "status" => "active")
      expect(booking["slot"]).to eq(
        "id" => slot.id, "starts_at" => "2030-03-04T09:00:00Z", "ends_at" => "2030-03-04T09:30:00Z"
      )
    end

    it "R6: a booked slot no longer appears as open" do
      post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json

      expect(open_slot_ids).not_to include(slot.id)
    end

    it "R19: books for the token's user, ignoring a user_id in the request" do
      post "/bookings", params: { slot_id: slot.id, user_id: other_user_id },
        headers: headers.merge("X-User-Id" => other_user_id), as: :json

      expect(Booking.find(response.parsed_body.dig("booking", "id")).user_id).to eq(user_id)
    end

    it "returns a 404 envelope for a slot that doesn't exist" do
      post "/bookings", params: { slot_id: SecureRandom.uuid }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(error_code).to eq("not_found")
    end

    it "returns a 409 booking_exists envelope when the user already has a booking" do
      create_booking(user_id: user_id)

      post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(error_code).to eq("booking_exists")
    end

    it "requires a signed-in user (401 envelope)" do
      post "/bookings", params: { slot_id: slot.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(Booking.count).to eq(0)
    end
  end

  describe "R7: booking a slot that is already booked" do
    let(:slot) { create_slot }
    let!(:original) { create_booking(user_id: other_user_id, slot: slot) }

    it "R7: is rejected with a 409 and a clear message" do
      post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(error_code).to eq("slot_taken")
      expect(response.parsed_body.dig("error", "message")).to match(/already booked/i)
      expect(response.parsed_body.dig("error", "actions")).to be_an(Array)
    end

    it "R7: leaves the original booking unchanged" do
      expect {
        post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json
      }.not_to(change { original.reload.attributes })
      expect(active_bookings_on(slot).pluck(:id)).to eq([ original.id ])
    end
  end

  describe "R8: bookings persist across sessions" do
    it "R8: a new token for the same user sees the booking" do
      slot = create_slot
      post "/bookings", params: { slot_id: slot.id }, headers: auth_headers(user_id), as: :json
      booking_id = response.parsed_body.dig("booking", "id")

      travel 2.hours do
        get "/bookings", headers: auth_headers(user_id, alg: "RS256")
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["bookings"].map { |booking| [ booking["id"], booking.dig("slot", "id") ] })
        .to eq([ [ booking_id, slot.id ] ])
    end

    it "lists only the caller's active bookings" do
      create_booking(user_id: other_user_id)
      create_booking(user_id: user_id, status: "cancelled")
      mine = create_booking(user_id: user_id, slot: create_slot(starts_at: 5.days.from_now.utc.change(min: 0, sec: 0)))

      get "/bookings", headers: headers

      expect(response.parsed_body["bookings"].map { |booking| booking["id"] }).to eq([ mine.id ])
    end
  end

  describe "GET /bookings/:id" do
    it "returns the booking with ISO-8601 UTC slot times (R37)" do
      booking = create_booking(user_id: user_id, slot: create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0)))

      get "/bookings/#{booking.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("booking", "slot", "starts_at")).to eq("2030-03-04T09:00:00Z")
    end
  end

  describe "PATCH /bookings/:id (R36 reschedule)" do
    let(:old_slot) { create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0)) }
    let(:new_slot) { create_slot(starts_at: Time.utc(2030, 3, 5, 14, 30)) }
    let!(:booking) { create_booking(user_id: user_id, slot: old_slot) }

    it "R36: moves the booking to another open slot and confirms the new time" do
      patch "/bookings/#{booking.id}", params: { slot_id: new_slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["booking"]).to include("status" => "active")
      expect(response.parsed_body.dig("booking", "slot")).to include("id" => new_slot.id, "starts_at" => "2030-03-05T14:30:00Z")
    end

    it "R36: the old slot is open again and the database reflects the change" do
      patch "/bookings/#{booking.id}", params: { slot_id: new_slot.id }, headers: headers, as: :json

      expect(active_bookings_on(old_slot)).to be_empty
      expect(Booking.where(user_id: user_id, status: "active").pluck(:slot_id)).to eq([ new_slot.id ])
      expect(open_slot_ids).to include(old_slot.id)
      expect(open_slot_ids).not_to include(new_slot.id)
    end

    it "R7: rejects a move to a booked slot with a 409 and leaves the booking unchanged" do
      create_booking(user_id: other_user_id, slot: new_slot)

      expect {
        patch "/bookings/#{booking.id}", params: { slot_id: new_slot.id }, headers: headers, as: :json
      }.not_to(change { booking.reload.attributes })
      expect(response).to have_http_status(:conflict)
      expect(error_code).to eq("slot_taken")
    end

    it "R19: another user can't reschedule it, and it stays unchanged" do
      expect {
        patch "/bookings/#{booking.id}", params: { slot_id: new_slot.id }, headers: auth_headers(other_user_id), as: :json
      }.not_to(change { booking.reload.attributes })
      expect(response.status).to be_in([ 403, 404 ])
    end
  end

  describe "DELETE /bookings/:id (R36 cancel)" do
    let(:slot) { create_slot }
    let!(:booking) { create_booking(user_id: user_id, slot: slot) }

    it "R36: cancels the booking" do
      delete "/bookings/#{booking.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("booking", "status")).to eq("cancelled")
    end

    it "R36: the slot is open again and the database reflects the change" do
      delete "/bookings/#{booking.id}", headers: headers

      expect(booking.reload.status).to eq("cancelled")
      expect(active_bookings_on(slot)).to be_empty
      expect(open_slot_ids).to include(slot.id)
    end

    it "R19: another user can't cancel it, and it stays active" do
      delete "/bookings/#{booking.id}", headers: auth_headers(other_user_id)

      expect(response.status).to be_in([ 403, 404 ])
      expect(booking.reload.status).to eq("active")
    end
  end

  describe "R19: user A can't read, reschedule or cancel user B's booking by ID" do
    let(:owner_id) { SecureRandom.uuid }
    let(:owned_booking) { create_booking(user_id: owner_id) }

    context "when reading" do
      it_behaves_like "an owner-scoped resource" do
        let(:path) { "/bookings/#{owned_booking.id}" }
      end
    end

    context "when rescheduling" do
      it_behaves_like "an owner-scoped resource", method: :patch do
        let(:path) { "/bookings/#{owned_booking.id}" }
        let(:params) { { slot_id: create_slot(starts_at: 6.days.from_now.utc.change(min: 0, sec: 0)).id } }
      end
    end

    context "when cancelling" do
      it_behaves_like "an owner-scoped resource", method: :delete do
        let(:path) { "/bookings/#{owned_booking.id}" }
      end
    end
  end

  describe "R24: every booking request logs its server time" do
    let(:slot) { create_slot }

    def booking_log_entry(output, method, path)
      log_lines(output).map { |line| JSON.parse(line) }
        .find { |entry| entry["method"] == method && entry["path"] == path }
    end

    it "R24: logs the duration of a booking" do
      output = capture_logs { post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json }

      expect(booking_log_entry(output, "POST", "/bookings")).to include("status" => 201, "duration" => be_a(Numeric))
    end

    it "R24: logs the duration of a rejected booking" do
      create_booking(user_id: other_user_id, slot: slot)

      output = capture_logs { post "/bookings", params: { slot_id: slot.id }, headers: headers, as: :json }

      expect(booking_log_entry(output, "POST", "/bookings")).to include("status" => 409, "duration" => be_a(Numeric))
    end

    it "R24: logs the duration of a reschedule and a cancellation" do
      booking = create_booking(user_id: user_id, slot: slot)
      new_slot = create_slot(starts_at: 7.days.from_now.utc.change(min: 0, sec: 0))
      path = "/bookings/#{booking.id}"

      output = capture_logs do
        patch path, params: { slot_id: new_slot.id }, headers: headers, as: :json
        delete path, headers: headers
      end

      expect(booking_log_entry(output, "PATCH", path)).to include("duration" => be_a(Numeric))
      expect(booking_log_entry(output, "DELETE", path)).to include("duration" => be_a(Numeric))
    end
  end

  describe "R7: 20 parallel requests for the same open slot (real Postgres, real threads)" do
    self.use_transactional_tests = false

    after do
      Booking.delete_all
      Slot.delete_all
    end

    it "R7: produce exactly 1 booking; the other 19 get a 409 slot_taken" do
      slot = create_slot
      requests = Array.new(20) { auth_headers(SecureRandom.uuid).merge("Content-Type" => "application/json") }

      responses = with_connection_pool_of(25) do
        in_parallel(requests) do |request_headers|
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post "/bookings", params: { slot_id: slot.id }.to_json, headers: request_headers
          [ session.response.status, session.response.parsed_body.dig("error", "code") ]
        end
      end

      expect(responses.tally).to eq([ 201, nil ] => 1, [ 409, "slot_taken" ] => 19)
      expect(Booking.where(slot_id: slot.id).count).to eq(1)
    end
  end

  describe "past slots can't be booked by ID" do
    let(:past_slot) { create_slot(starts_at: 1.day.ago.utc.change(min: 0, sec: 0)) }

    it "POST /bookings for a past slot returns 422 slot_in_past and books nothing" do
      post "/bookings", params: { slot_id: past_slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(error_code).to eq("slot_in_past")
      expect(response.parsed_body.dig("error", "message")).to be_present
      expect(Booking.where(user_id: user_id)).to be_empty
    end

    it "PATCH /bookings/:id into a past slot returns 422 slot_in_past and keeps the booking" do
      booking = create_booking(user_id: user_id)
      original_slot_id = booking.slot_id

      patch "/bookings/#{booking.id}", params: { slot_id: past_slot.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(error_code).to eq("slot_in_past")
      expect(booking.reload).to have_attributes(slot_id: original_slot_id, status: "active")
    end
  end
end
