# Grants and revokes versioned consent to process an ID image (R12, R13). Each grant is its own
# consents row; revoking ends every active grant. The OCR path writes its draft inside
# with_active_consent, which holds a row lock that revoke! has to wait for, so a revocation
# either lands before the draft write (and no draft is written) or after it (and the purge that
# follows a revocation sees the draft).
class Consent::Ledger
  # Raised by with_active_consent when the user has no active consent.
  class NotGiven < StandardError; end

  def self.grant!(user_id:, text_version:)
    Consent.create!(user_id: user_id, text_version: text_version, granted_at: Time.current)
  end

  def self.revoke!(user_id:)
    Consent.active.where(user_id: user_id).update_all(revoked_at: Time.current, updated_at: Time.current)
  end

  def self.active?(user_id)
    Consent.active.exists?(user_id: user_id)
  end

  # True once a user who consented has revoked it, so chat stops calling the LLM (R13). A user
  # who never consented hasn't withdrawn anything.
  def self.withdrawn?(user_id)
    Consent.exists?(user_id: user_id) && !active?(user_id)
  end

  # Runs the block in a transaction that holds a lock on the user's active consent rows, and
  # returns its value. Raises NotGiven without running it when there is no active consent.
  def self.with_active_consent(user_id)
    Consent.transaction do
      raise NotGiven, "no active consent" if Consent.active.where(user_id: user_id).lock.pluck(:id).empty?

      yield
    end
  end
end
