# The user's onboarding record. Identity values are written only when the user confirms them,
# from a reviewed OCR draft or typed in by hand (R5, R10), and are encrypted at rest (R18).
class Onboarding < ApplicationRecord
  IDENTITY_FIELDS = %i[full_name date_of_birth address].freeze
  IDENTITY_SOURCES = %w[ocr manual].freeze

  has_many :document_uploads, dependent: :delete_all

  attribute :date_of_birth, :date
  encrypts :full_name, :date_of_birth, :address
  normalizes :full_name, :address, with: ->(value) { value.strip }

  validates :identity_source, inclusion: { in: IDENTITY_SOURCES }, allow_nil: true
  with_options if: :identity_source? do
    validates :full_name, :address, :confirmed_at, presence: true
    validate :date_of_birth_is_a_real_past_date
  end

  def self.for_user(user_id)
    find_or_create_by!(user_id: user_id)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Saves the three identity fields exactly as given (a missing one counts as blank), raising ActiveRecord::RecordInvalid (and
  # changing nothing) when one is blank or the date isn't a real date in the past.
  def confirm_identity!(fields, source:)
    given = fields.to_h.symbolize_keys
    update!(IDENTITY_FIELDS.index_with { |field| given[field] }.merge(identity_source: source, confirmed_at: Time.current))
  end

  def identity
    slice(*IDENTITY_FIELDS, :identity_source, :confirmed_at)
  end

  private

  # The date column casts "1985-02-30" to nil, so the raw input is checked as well.
  def date_of_birth_is_a_real_past_date
    raw = date_of_birth_before_type_cast
    if date_of_birth.nil? || (raw.is_a?(String) && !raw.match?(/\A\d{4}-\d{2}-\d{2}\z/))
      errors.add(:date_of_birth, :invalid)
    elsif date_of_birth > Date.current
      errors.add(:date_of_birth, "can't be in the future")
    end
  end
end
