# Slots and bookings (R6, R7, R37). Times are timestamptz so Postgres stores the UTC instant. The
# partial unique indexes are the double-booking guarantee: one active booking per slot and per
# user, enforced by the database even for code that skips Scheduling::Booker.
class CreateSlotsAndBookings < ActiveRecord::Migration[8.1]
  def change
    create_table :slots, id: :uuid do |t|
      t.timestamptz :starts_at, null: false
      t.timestamptz :ends_at, null: false
      t.timestamps
      t.index :starts_at
    end

    create_table :bookings, id: :uuid do |t|
      t.references :slot, type: :uuid, null: false, foreign_key: true, index: false
      t.uuid :user_id, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
      t.index :slot_id, unique: true, where: "status = 'active'", name: "index_bookings_on_slot_id_active"
      t.index :user_id, unique: true, where: "status = 'active'", name: "index_bookings_on_user_id_active"
      t.check_constraint "status IN ('active', 'cancelled')", name: "bookings_status_check"
    end
  end
end
