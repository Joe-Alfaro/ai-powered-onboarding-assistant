require "rails_helper"

# Described by name so a missing class fails each example with a NameError instead of
# stopping the whole suite at load time.
RSpec.describe "Scheduling::Booker" do
  let(:user_id) { SecureRandom.uuid }
  let(:other_user_id) { SecureRandom.uuid }
  let(:booker) { Scheduling::Booker.new(user_id: user_id) }

  describe "#book (R6)" do
    let(:slot) { create_slot }

    it "R6: books an open slot and returns a booked result with the slot" do
      result = booker.book(slot_id: slot.id)

      expect(result).to be_success
      expect(result.outcome).to eq(:booked)
      expect(result.slot).to eq(slot)
      expect(result.booking).to be_persisted
      expect(result.booking).to have_attributes(user_id: user_id, slot_id: slot.id, status: "active")
    end

    it "R8: keys the booking by the user it was built for" do
      booker.book(slot_id: slot.id)

      expect(Booking.where(user_id: user_id, status: "active").pluck(:slot_id)).to eq([ slot.id ])
    end

    it "returns not_found for a slot that doesn't exist" do
      result = booker.book(slot_id: SecureRandom.uuid)

      expect(result).not_to be_success
      expect(result.outcome).to eq(:not_found)
      expect(Booking.count).to eq(0)
    end

    it "returns booking_exists when the user already holds an active booking, and keeps it" do
      existing = create_booking(user_id: user_id)

      result = booker.book(slot_id: slot.id)

      expect(result.outcome).to eq(:booking_exists)
      expect(result.booking).to eq(existing)
      expect(active_bookings_on(slot)).to be_empty
    end
  end

  describe "R7: booking a slot that is already booked" do
    let(:slot) { create_slot }
    let!(:original) { create_booking(user_id: other_user_id, slot: slot) }

    it "R7: is rejected with a slot_taken result" do
      result = booker.book(slot_id: slot.id)

      expect(result).not_to be_success
      expect(result.outcome).to eq(:slot_taken)
      expect(result.slot).to eq(slot)
    end

    it "R7: leaves the original booking unchanged" do
      expect { booker.book(slot_id: slot.id) }.not_to(change { original.reload.attributes })
      expect(active_bookings_on(slot).pluck(:id)).to eq([ original.id ])
    end
  end

  describe "#reschedule (R36)" do
    let(:old_slot) { create_slot(starts_at: 2.days.from_now.utc.change(hour: 9, min: 0, sec: 0)) }
    let(:new_slot) { create_slot(starts_at: 3.days.from_now.utc.change(hour: 14, min: 0, sec: 0)) }
    let!(:booking) { create_booking(user_id: user_id, slot: old_slot) }

    it "R36: moves the booking to another open slot" do
      result = booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(result).to be_success
      expect(result.outcome).to eq(:rescheduled)
      expect(result.slot).to eq(new_slot)
      expect(result.previous_slot).to eq(old_slot)
      expect(result.booking).to have_attributes(user_id: user_id, slot_id: new_slot.id, status: "active")
    end

    it "R36: leaves the old slot open again in the database" do
      booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(active_bookings_on(old_slot)).to be_empty
      expect(Booking.where(user_id: user_id, status: "active").pluck(:slot_id)).to eq([ new_slot.id ])
    end

    it "R36: lets someone else book the old slot afterwards" do
      booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(Scheduling::Booker.new(user_id: other_user_id).book(slot_id: old_slot.id).outcome).to eq(:booked)
    end

    it "R7: rejects a move to a slot that is already booked and leaves the booking unchanged" do
      create_booking(user_id: other_user_id, slot: new_slot)

      result = nil
      expect { result = booker.reschedule(booking_id: booking.id, slot_id: new_slot.id) }
        .not_to(change { booking.reload.attributes })
      expect(result.outcome).to eq(:slot_taken)
      expect(active_bookings_on(old_slot).pluck(:id)).to eq([ booking.id ])
    end

    it "returns not_found for a target slot that doesn't exist and leaves the booking unchanged" do
      result = booker.reschedule(booking_id: booking.id, slot_id: SecureRandom.uuid)

      expect(result.outcome).to eq(:not_found)
      expect(booking.reload).to have_attributes(slot_id: old_slot.id, status: "active")
    end

    it "R19: returns not_found for another user's booking and leaves it unchanged" do
      result = Scheduling::Booker.new(user_id: other_user_id).reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(result.outcome).to eq(:not_found)
      expect(booking.reload).to have_attributes(slot_id: old_slot.id, status: "active")
    end
  end

  describe "#cancel (R36)" do
    let(:slot) { create_slot }
    let!(:booking) { create_booking(user_id: user_id, slot: slot) }

    it "R36: cancels the booking and reports the slot it freed" do
      result = booker.cancel(booking_id: booking.id)

      expect(result).to be_success
      expect(result.outcome).to eq(:cancelled)
      expect(result.previous_slot).to eq(slot)
      expect(booking.reload.status).to eq("cancelled")
    end

    it "R36: leaves the slot open again in the database" do
      booker.cancel(booking_id: booking.id)

      expect(active_bookings_on(slot)).to be_empty
      expect(Scheduling::Booker.new(user_id: other_user_id).book(slot_id: slot.id).outcome).to eq(:booked)
    end

    it "lets the user book again after cancelling" do
      booker.cancel(booking_id: booking.id)

      expect(booker.book(slot_id: create_slot(starts_at: 4.days.from_now.utc.change(min: 0, sec: 0)).id).outcome).to eq(:booked)
    end

    it "R19: returns not_found for another user's booking and leaves it active" do
      result = Scheduling::Booker.new(user_id: other_user_id).cancel(booking_id: booking.id)

      expect(result.outcome).to eq(:not_found)
      expect(booking.reload.status).to eq("active")
    end

    it "returns not_found for a booking that is already cancelled" do
      booker.cancel(booking_id: booking.id)

      expect(booker.cancel(booking_id: booking.id).outcome).to eq(:not_found)
    end
  end

  describe "result object (for chat reply templates, R3/R36)" do
    let(:old_slot) do
      create_slot(starts_at: Time.utc(2030, 3, 4, 9, 0), length: 30.minutes)
    end
    let(:new_slot) do
      create_slot(starts_at: Time.utc(2030, 3, 5, 14, 30), length: 30.minutes)
    end
    let!(:booking) { create_booking(user_id: user_id, slot: old_slot) }

    it "serializes a reschedule to plain data with ISO-8601 UTC times" do
      result = booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(result.to_h).to eq(
        outcome: "rescheduled",
        booking_id: result.booking.id,
        slot: { id: new_slot.id, starts_at: "2030-03-05T14:30:00Z", ends_at: "2030-03-05T15:00:00Z" },
        previous_slot: { id: old_slot.id, starts_at: "2030-03-04T09:00:00Z", ends_at: "2030-03-04T09:30:00Z" }
      )
    end

    it "serializes a cancellation with no current slot" do
      result = booker.cancel(booking_id: booking.id)

      expect(result.to_h).to eq(
        outcome: "cancelled",
        booking_id: booking.id,
        slot: nil,
        previous_slot: { id: old_slot.id, starts_at: "2030-03-04T09:00:00Z", ends_at: "2030-03-04T09:30:00Z" }
      )
    end

    it "serializes a rejection with the requested slot and no booking change" do
      create_booking(user_id: other_user_id, slot: new_slot)

      result = booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

      expect(result.to_h).to include(outcome: "slot_taken",
        slot: { id: new_slot.id, starts_at: "2030-03-05T14:30:00Z", ends_at: "2030-03-05T15:00:00Z" })
    end

    it "R37: serializes in UTC even when the app's time zone is not UTC" do
      Time.use_zone("Pacific/Auckland") do
        result = booker.reschedule(booking_id: booking.id, slot_id: new_slot.id)

        expect(result.to_h.dig(:slot, :starts_at)).to eq("2030-03-05T14:30:00Z")
      end
    end
  end

  describe "R7: 20 parallel bookings of the same open slot (real Postgres, real threads)" do
    self.use_transactional_tests = false

    after do
      Booking.delete_all
      Slot.delete_all
    end

    it "R7: produces exactly 1 booking; the other 19 get slot_taken" do
      slot = create_slot
      users = Array.new(20) { SecureRandom.uuid }

      outcomes = with_connection_pool_of(25) do
        in_parallel(users) { |id| Scheduling::Booker.new(user_id: id).book(slot_id: slot.id).outcome }
      end

      expect(outcomes.tally).to eq(booked: 1, slot_taken: 19)
      expect(Booking.where(slot_id: slot.id).count).to eq(1)
    end
  end

  # Booking by ID must not reach slots the slot list hides: a slot that has already started can't
  # be booked or rescheduled into.
  describe "past slots" do
    let(:past_slot) { create_slot(starts_at: 1.day.ago.utc.change(min: 0, sec: 0)) }
    let(:started_slot) { create_slot(starts_at: 10.minutes.ago, length: 30.minutes) }

    it "rejects booking a past slot by ID as slot_in_past and creates no booking" do
      result = booker.book(slot_id: past_slot.id)

      expect(result).not_to be_success
      expect(result.outcome).to eq(:slot_in_past)
      expect(result.booking).to be_nil
      expect(Booking.where(slot_id: past_slot.id)).to be_empty
    end

    it "rejects booking a slot that has already started" do
      result = booker.book(slot_id: started_slot.id)

      expect(result.outcome).to eq(:slot_in_past)
      expect(Booking.where(slot_id: started_slot.id)).to be_empty
    end

    it "rejects rescheduling into a past slot and leaves the booking unchanged" do
      booking = create_booking(user_id: user_id)

      result = nil
      expect { result = booker.reschedule(booking_id: booking.id, slot_id: past_slot.id) }
        .not_to(change { booking.reload.attributes })
      expect(result).not_to be_success
      expect(result.outcome).to eq(:slot_in_past)
    end
  end
end
