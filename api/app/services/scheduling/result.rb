module Scheduling
  # What Scheduling::Booker did, failures included, so callers (the bookings API and the chat
  # `request-reschedule` handler) can build replies from real data (R3, R36). `slot` is the slot
  # now held or requested; `previous_slot` is the slot freed.
  Result = Data.define(:outcome, :booking, :slot, :previous_slot) do
    def initialize(outcome:, booking: nil, slot: nil, previous_slot: nil)
      super
    end

    def success?
      %i[booked rescheduled cancelled].include?(outcome)
    end

    def to_h
      {
        outcome: outcome.to_s,
        booking_id: booking&.id,
        slot: slot&.summary,
        previous_slot: previous_slot&.summary
      }
    end
  end
end
