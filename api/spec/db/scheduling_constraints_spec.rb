require "rails_helper"

# R7: the database itself refuses a double booking, so the guarantee holds even for code that
# skips Scheduling::Booker. R37: slot times are stored as timestamptz in UTC.
RSpec.describe "Scheduling database constraints" do
  let(:connection) { ActiveRecord::Base.connection }

  def index_on(column)
    connection.indexes(:bookings).find { |index| index.columns == [ column ] && index.unique }
  end

  # Inserts without validations, callbacks or any Booker check.
  def insert_booking(user_id:, slot:, status: "active")
    Booking.insert!({ user_id: user_id, slot_id: slot.id, status: status })
  end

  describe "R7: the database enforces one active booking per slot" do
    it "R7: has a partial unique index on bookings.slot_id where status is active" do
      index = index_on("slot_id")

      expect(index).to be_present
      expect(index.where).to match(/status.*=.*'active'/)
    end

    it "R7: rejects a second active booking for a slot even when the app check is bypassed" do
      slot = create_slot
      insert_booking(user_id: SecureRandom.uuid, slot: slot)

      expect { insert_booking(user_id: SecureRandom.uuid, slot: slot) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new active booking on a slot whose earlier booking was cancelled" do
      slot = create_slot
      insert_booking(user_id: SecureRandom.uuid, slot: slot, status: "cancelled")

      expect { insert_booking(user_id: SecureRandom.uuid, slot: slot) }.not_to raise_error
    end
  end

  describe "the database enforces one active booking per user" do
    it "has a partial unique index on bookings.user_id where status is active" do
      index = index_on("user_id")

      expect(index).to be_present
      expect(index.where).to match(/status.*=.*'active'/)
    end

    it "rejects a second active booking for the same user even when the app check is bypassed" do
      user_id = SecureRandom.uuid
      insert_booking(user_id: user_id, slot: create_slot)

      expect {
        insert_booking(user_id: user_id, slot: create_slot(starts_at: 5.days.from_now.utc.change(min: 0, sec: 0)))
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "R37: slot times are stored in UTC" do
    it "R37: stores starts_at and ends_at as timestamptz" do
      expect(Slot.columns_hash.values_at("starts_at", "ends_at").map(&:sql_type)).to all(eq("timestamp with time zone"))
    end

    it "R37: stores the UTC instant of a time given in another zone" do
      local = ActiveSupport::TimeZone["America/Los_Angeles"].parse("2030-07-01 09:00")
      slot = create_slot(starts_at: local)

      stored = connection.select_value(<<~SQL.squish)
        SELECT to_char(starts_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS') FROM slots WHERE id = #{connection.quote(slot.id)}
      SQL
      expect(stored).to eq("2030-07-01T16:00:00")
    end
  end
end
