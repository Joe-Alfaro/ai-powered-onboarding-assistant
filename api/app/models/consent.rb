# One grant of consent to process an ID image (R12). A grant is never edited except to record its
# revocation; consenting again makes a new row with the text version shown at the time.
# Consent::Ledger is the only writer.
class Consent < ApplicationRecord
  # The consent text the web app shows now. Must match CONSENT_TEXT_VERSION in
  # web/src/identity/ConsentForm.tsx; older rows keep the version they were granted under.
  CURRENT_TEXT_VERSION = "2026-10-15".freeze

  scope :active, -> { where(revoked_at: nil) }

  validates :user_id, :text_version, :granted_at, presence: true
end
