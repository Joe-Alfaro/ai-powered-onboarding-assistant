# An uploaded ID image waiting for the user to confirm its fields (R5, R17). The image lives in
# the private Storage bucket under storage_key, which never includes the uploaded filename. The
# OCR output stays in draft_fields (only the three identity fields, each with its confidence)
# until confirmation clears it. Unconfirmed uploads are purged after TTL.
class DocumentUpload < ApplicationRecord
  TTL = 1.hour
  STATUSES = %w[pending confirmed].freeze

  belongs_to :onboarding

  serialize :draft_fields, coder: JSON
  encrypts :draft_fields

  validates :storage_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :expired, -> { pending.where(expires_at: ..Time.current) }

  def self.pending_for(user_id)
    pending.joins(:onboarding).where(onboardings: { user_id: user_id })
  end

  # The draft as the API returns it. manual_entry is true when OCR couldn't read the fields, and
  # reason says why (an Ocr::Result reason).
  def summary
    fields = draft_fields.to_h
    {
      id: id,
      status: status,
      manual_entry: ocr_reason.present?,
      reason: ocr_reason,
      fields: Onboarding::IDENTITY_FIELDS.index_with { |field| fields[field.to_s] }
    }
  end
end
