# The user's saved assessment (R2). Only data that validates against the committed schema is ever
# saved, so the model checks it again before every write.
class Assessment < ApplicationRecord
  serialize :data, coder: JSON
  encrypts :data

  validates :schema_version, presence: true
  validate :data_matches_schema

  private

  def data_matches_schema
    errors.add(:data, "doesn't match the assessment schema") unless Chat::AssessmentSchema.valid?(data)
  end
end
