require "rails_helper"

RSpec.describe "Slots API", type: :request do
  let(:user_id) { SecureRandom.uuid }
  let(:headers) { auth_headers(user_id) }

  def open_slot_ids
    get "/slots", headers: headers
    response.parsed_body["slots"].map { |slot| slot["id"] }
  end

  describe "GET /slots" do
    it "R6: a signed-in user sees open slots with their times" do
      slot = create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0), length: 30.minutes)

      get "/slots", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["slots"]).to eq([
        { "id" => slot.id, "starts_at" => "2030-03-04T09:00:00Z", "ends_at" => "2030-03-04T09:30:00Z" }
      ])
    end

    it "R6: a booked slot no longer appears as open" do
      booked = create_slot(starts_at: 2.days.from_now.utc.change(min: 0, sec: 0))
      open = create_slot(starts_at: 3.days.from_now.utc.change(min: 0, sec: 0))
      create_booking(user_id: SecureRandom.uuid, slot: booked)

      expect(open_slot_ids).to eq([ open.id ])
    end

    it "lists a slot whose only booking was cancelled as open" do
      slot = create_slot
      create_booking(user_id: SecureRandom.uuid, slot: slot, status: "cancelled")

      expect(open_slot_ids).to eq([ slot.id ])
    end

    it "lists only future slots, soonest first" do
      later = create_slot(starts_at: 3.days.from_now.utc.change(min: 0, sec: 0))
      sooner = create_slot(starts_at: 1.day.from_now.utc.change(min: 0, sec: 0))
      create_slot(starts_at: 1.day.ago.utc.change(min: 0, sec: 0))

      expect(open_slot_ids).to eq([ sooner.id, later.id ])
    end

    it "R37: returns times as ISO-8601 UTC even when the server's time zone is not UTC" do
      create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0))
      original_zone = Time.zone
      Time.zone = "Asia/Tokyo"

      get "/slots", headers: headers

      slot = response.parsed_body["slots"].first
      expect(slot["starts_at"]).to eq("2030-03-04T09:00:00Z")
      expect(slot.values_at("starts_at", "ends_at")).to all(match(SchedulingHelpers::ISO_8601_UTC))
    ensure
      Time.zone = original_zone
    end

    it "requires a signed-in user (401 envelope)" do
      get "/slots"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body.dig("error", "code")).to eq("unauthorized")
    end
  end

  describe "the slot list never shows past slots" do
    it "hides a slot that has already started, even though it hasn't ended" do
      create_slot(starts_at: 10.minutes.ago, length: 30.minutes)
      future = create_slot

      expect(open_slot_ids).to eq([ future.id ])
    end
  end
end
