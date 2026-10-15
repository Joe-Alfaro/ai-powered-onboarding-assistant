# One chat per user. The assessment draft holds the fields validated so far, until they are
# complete enough to save as an Assessment.
class Conversation < ApplicationRecord
  has_many :messages, -> { order(:created_at) }, dependent: :delete_all, inverse_of: :conversation

  serialize :assessment_draft, coder: JSON
  encrypts :assessment_draft

  def self.for_user(user_id)
    find_or_initialize_by(user_id: user_id)
  end

  def draft
    assessment_draft || {}
  end

  def recent_messages(limit)
    new_record? ? [] : messages.reorder(created_at: :desc).limit(limit).to_a.reverse
  end
end
