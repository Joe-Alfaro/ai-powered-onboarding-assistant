# A user's hold on a slot (R6, R8). Cancelled rows stay as history; the partial unique indexes
# allow one active booking per slot and per user (R7).
class Booking < ApplicationRecord
  STATUSES = %w[active cancelled].freeze

  belongs_to :slot

  validates :user_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }

  def summary
    { id: id, status: status, slot: slot.summary }
  end
end
