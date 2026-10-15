# One row per admin access (R19). The actor is a keyed HMAC of their user ID, so the log names no
# one directly and can't be reversed by hashing guessed IDs.
class AuditEvent < ApplicationRecord
  validates :actor_ref, :action, presence: true

  def self.record!(user_id:, action:)
    create!(actor_ref: actor_ref_for(user_id), action: action)
  end

  def self.actor_ref_for(user_id)
    OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("AUDIT_HMAC_KEY"), user_id)
  end
end
