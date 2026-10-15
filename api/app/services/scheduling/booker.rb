module Scheduling
  # Books, reschedules and cancels one user's appointment (R6, R7, R36). Each change runs in its
  # own transaction and returns a Result instead of raising. The partial unique indexes on
  # bookings are the real double-booking guard: the checks here only pick a clearer outcome, and
  # a unique violation from a lost race maps to the same outcome.
  class Booker
    SLOT_INDEX = "index_bookings_on_slot_id_active".freeze

    def initialize(user_id:)
      @user_id = user_id
    end

    def book(slot_id:)
      slot = Slot.find_by(id: slot_id)
      return Result.new(outcome: :not_found) unless slot

      existing = own_bookings.active.first
      return Result.new(outcome: :booking_exists, booking: existing, slot: existing.slot) if existing
      return slot_taken(slot) if slot.bookings.active.exists?

      booking = in_transaction { Booking.create!(user_id: user_id, slot: slot, status: "active") }
      Result.new(outcome: :booked, booking: booking, slot: slot)
    rescue ActiveRecord::RecordNotUnique => e
      slot_violation?(e) ? slot_taken(slot) : book_conflict
    end

    def reschedule(booking_id:, slot_id:)
      in_transaction do
        booking = own_bookings.active.lock.find_by(id: booking_id)
        new_slot = Slot.find_by(id: slot_id)
        next Result.new(outcome: :not_found) unless booking && new_slot

        previous_slot = booking.slot
        booking.update!(slot: new_slot)
        Result.new(outcome: :rescheduled, booking: booking, slot: new_slot, previous_slot: previous_slot)
      end
    rescue ActiveRecord::RecordNotUnique
      slot_taken(Slot.find(slot_id))
    end

    def cancel(booking_id:)
      in_transaction do
        booking = own_bookings.active.lock.find_by(id: booking_id)
        next Result.new(outcome: :not_found) unless booking

        booking.update!(status: "cancelled")
        Result.new(outcome: :cancelled, booking: booking, previous_slot: booking.slot)
      end
    end

    private
      attr_reader :user_id

      # Bookings are always looked up through the user, so another user's ID reads as not found
      # (R19).
      def own_bookings
        Booking.where(user_id: user_id)
      end

      # A savepoint when nested, so a unique violation doesn't abort the caller's transaction.
      def in_transaction(&)
        Booking.transaction(requires_new: true, &)
      end

      def slot_taken(slot)
        Result.new(outcome: :slot_taken, slot: slot)
      end

      # Lost a race on the per-user index: another request booked for this user first.
      def book_conflict
        existing = own_bookings.active.first
        Result.new(outcome: :booking_exists, booking: existing, slot: existing&.slot)
      end

      def slot_violation?(error)
        error.cause.respond_to?(:result) &&
          error.cause.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME) == SLOT_INDEX
      end
  end
end
