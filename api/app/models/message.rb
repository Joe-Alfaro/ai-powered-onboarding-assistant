class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :conversation

  encrypts :content

  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true
end
