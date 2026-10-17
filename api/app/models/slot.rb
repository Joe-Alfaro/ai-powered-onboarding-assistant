# A bookable appointment time. Times are stored as timestamptz and always leave the API as
# ISO-8601 UTC, whatever the server's time zone is (R37).
class Slot < ApplicationRecord
  has_many :bookings, dependent: :restrict_with_exception

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start

  # Future slots with no active booking, soonest first (R6).
  scope :open, -> { where(starts_at: Time.current..).where.not(id: Booking.active.select(:slot_id)).order(:starts_at) }

  # A slot that has started can't be booked, even before it ends.
  def past?
    starts_at <= Time.current
  end

  def summary
    { id: id, starts_at: starts_at.utc.iso8601, ends_at: ends_at.utc.iso8601 }
  end

  private
    def ends_after_start
      errors.add(:ends_at, "must be after starts_at") if starts_at && ends_at && ends_at <= starts_at
    end
end
