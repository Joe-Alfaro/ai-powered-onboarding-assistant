# One grant of consent to process an ID image (R12). A grant is never edited except to record its
# revocation; consenting again makes a new row with the text version shown at the time.
# Consent::Ledger is the only writer.
class Consent < ApplicationRecord
  scope :active, -> { where(revoked_at: nil) }

  validates :user_id, :text_version, :granted_at, presence: true
end
