module Privacy
  # Consent withdrawal and account deletion (R13). Both revoke consent first, so chat and any OCR
  # upload in flight stop processing, then hard-delete the user's identity, uploads and their
  # images, conversation, messages and assessment, and write one audit entry that names the user
  # only by an HMAC. Deletion also deletes the user's bookings, which frees an active booking's
  # slot, and their Supabase Auth account. The revoked consent rows stay, so a still-valid token
  # keeps getting 403 from chat. Every step is safe to repeat.
  class Purger
    def initialize(user_id:, storage: Storage::Client.default, auth_admin: Auth::AdminClient.default)
      @user_id = user_id
      @storage = storage
      @auth_admin = auth_admin
    end

    def withdraw_consent
      purge(action: "consent_withdrawn")
    end

    def delete_account
      purge(action: "account_deleted") { Booking.where(user_id: @user_id).delete_all }
      @auth_admin.delete_user(@user_id)
    end

    private

    # Storage is called inside the transaction: if an image can't be deleted, the rows come back
    # and a retry finds them, rather than leaving an image nothing points to.
    def purge(action:)
      Consent::Ledger.revoke!(user_id: @user_id)
      ActiveRecord::Base.transaction do
        onboardings = Onboarding.where(user_id: @user_id)
        uploads = DocumentUpload.where(onboarding_id: onboardings.select(:id))
        keys = uploads.pluck(:storage_key)
        uploads.delete_all
        onboardings.delete_all
        conversations = Conversation.where(user_id: @user_id)
        Message.where(conversation_id: conversations.select(:id)).delete_all
        conversations.delete_all
        Assessment.where(user_id: @user_id).delete_all
        yield if block_given?
        keys.each { |key| @storage.delete(key) }
        AuditEvent.record!(user_id: @user_id, action: action)
      end
    end
  end
end
